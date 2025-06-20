import os
import uuid
import json
from datetime import datetime, timezone
from typing import List, Dict, Optional, Tuple
import asyncio
import asyncpg
import numpy as np
from sentence_transformers import SentenceTransformer
from google import genai
from google.genai import types
import logging

# Configuration
GOOGLE_GENAI_API_KEY = os.getenv('GOOGLE_GENAI_API_KEY')
DATABASE_URL = os.getenv('DATABASE_URL')
TEMPERATURE_SCORE = 0.7
SIMILARITY_THRESHOLD = 0.7
MAX_CONTEXT_CHUNKS = 5

if not GOOGLE_GENAI_API_KEY or not DATABASE_URL:
    raise EnvironmentError("Missing required environment variables.")

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class VietnameseRAGSystem:
    def __init__(self):
        self.embedding_model = SentenceTransformer("intfloat/multilingual-e5-base")
        self.embedding_dim = 768

        genai.configure(api_key=GOOGLE_GENAI_API_KEY)
        self.client = genai.Client(api_key=GOOGLE_GENAI_API_KEY)
        self.db_pool = None

    async def initialize_db_pool(self):
        self.db_pool = await asyncpg.create_pool(
            DATABASE_URL, min_size=5, max_size=20, command_timeout=60
        )
        async with self.db_pool.acquire() as conn:
            await conn.execute("CREATE EXTENSION IF NOT EXISTS vector;")

    async def close_db_pool(self):
        if self.db_pool:
            await self.db_pool.close()

    def generate_embedding(self, text: str) -> List[float]:
        try:
            cleaned_text = self._preprocess_vietnamese_text(text)
            embedding = self.embedding_model.encode(cleaned_text, normalize_embeddings=True)
            return [float(x) for x in embedding]  # Ensure Python floats
        except Exception as e:
            logger.error(f"Error generating embedding: {e}")
            return [0.0] * self.embedding_dim

    def _preprocess_vietnamese_text(self, text: str) -> str:
        text = text.strip().lower()
        return ' '.join(text.split())

    async def add_product_to_knowledge_base(self, product_id: str, name: str, specs: Dict, content: str) -> bool:
        try:
            full_text = f"{name} {content} {json.dumps(specs, ensure_ascii=False)}"
            embedding = self.generate_embedding(full_text)
            async with self.db_pool.acquire() as conn:
                await conn.execute("""
                    INSERT INTO product_vectors (id, product_id, name, specs, content, embedding)
                    VALUES ($1, $2, $3, $4, $5, $6)
                    ON CONFLICT (product_id) DO UPDATE SET
                        name = EXCLUDED.name,
                        specs = EXCLUDED.specs,
                        content = EXCLUDED.content,
                        embedding = EXCLUDED.embedding
                """, str(uuid.uuid4()), product_id, name, json.dumps(specs), content, embedding)
            logger.info(f"Added/updated product {product_id} in knowledge base")
            return True
        except Exception as e:
            logger.error(f"Error adding product to knowledge base: {e}")
            return False

    async def retrieve_relevant_context(self, query: str, visitor_id: str = None) -> Tuple[str, List[Dict]]:
        try:
            query_embedding = self.generate_embedding(query)
            async with self.db_pool.acquire() as conn:
                results = await conn.fetch("""
                    SELECT product_id, name, specs, content,
                           (embedding <=> $1::vector) as distance
                    FROM product_vectors
                    WHERE (embedding <=> $1::vector) < $2
                    ORDER BY distance
                    LIMIT $3
                """, query_embedding, 1 - SIMILARITY_THRESHOLD, MAX_CONTEXT_CHUNKS)

                user_context = await self._get_user_context(visitor_id) if visitor_id else {}

                relevant_docs = []
                context_parts = []
                for row in results:
                    doc_info = {
                        'product_id': row['product_id'],
                        'name': row['name'],
                        'specs': row['specs'],
                        'content': row['content'],
                        'similarity': 1 - row['distance']
                    }
                    relevant_docs.append(doc_info)
                    context_parts.append(f"""
                    Sản phẩm: {row['name']}
                    Thông số: {json.dumps(row['specs'], ensure_ascii=False)}
                    Mô tả: {row['content']}
                    """)

                if user_context:
                    context_parts.insert(0, f"Thông tin khách hàng: {json.dumps(user_context, ensure_ascii=False)}")

                combined_context = "\n---\n".join(context_parts)
                return combined_context, relevant_docs
        except Exception as e:
            logger.error(f"Error retrieving context: {e}")
            return "", []

    async def _get_user_context(self, visitor_id: str) -> Dict:
        try:
            async with self.db_pool.acquire() as conn:
                contact_info = await conn.fetchrow("""
                    SELECT name, email, phone, consent, created_at
                    FROM cdp_contacts
                    WHERE visitor_id = $1
                """, visitor_id)

                memory_info = await conn.fetchrow("""
                    SELECT memory, updated_at
                    FROM cdp_agent_memory
                    WHERE visitor_id = $1
                    ORDER BY updated_at DESC
                    LIMIT 1
                """, visitor_id)

                user_context = {}
                if contact_info:
                    user_context.update({
                        'name': contact_info['name'],
                        'email': contact_info['email'],
                        'phone': contact_info['phone'],
                        'customer_since': contact_info['created_at'].isoformat() if contact_info['created_at'] else None
                    })

                if memory_info and memory_info['memory']:
                    user_context['conversation_history'] = memory_info['memory']

                return user_context
        except Exception as e:
            logger.error(f"Error getting user context: {e}")
            return {}

    async def update_user_memory(self, visitor_id: str, session_id: str, interaction: Dict):
        try:
            async with self.db_pool.acquire() as conn:
                existing = await conn.fetchrow("""
                    SELECT memory FROM cdp_agent_memory 
                    WHERE visitor_id = $1 AND session_id = $2
                """, visitor_id, session_id)

                if existing and existing['memory']:
                    memory = existing['memory']
                    if 'interactions' not in memory:
                        memory['interactions'] = []
                    memory['interactions'].append(interaction)
                    memory['interactions'] = memory['interactions'][-10:]
                else:
                    memory = {
                        'interactions': [interaction],
                        'preferences': {},
                        'interests': []
                    }

                await conn.execute("""
                    INSERT INTO cdp_agent_memory (visitor_id, session_id, memory, updated_at)
                    VALUES ($1, $2, $3, $4)
                    ON CONFLICT (visitor_id, session_id) DO UPDATE SET
                        memory = EXCLUDED.memory,
                        updated_at = EXCLUDED.updated_at
                """, visitor_id, session_id, json.dumps(memory), datetime.now(timezone.utc))
        except Exception as e:
            logger.error(f"Error updating user memory: {e}")

    async def ask_question(self, question: str = 'Xin chào', visitor_id: str = None, session_id: str = None, temperature_score: float = TEMPERATURE_SCORE) -> Dict:
        try:
            context, relevant_docs = await self.retrieve_relevant_context(question, visitor_id)

            system_prompt = """Bạn là LEO, trợ lý AI thông minh và thân thiện của công ty. 
            Bạn có khả năng hiểu và trả lời bằng tiếng Việt một cách tự nhiên.
            Nhiệm vụ của bạn:
            1. Trả lời câu hỏi của khách hàng dựa trên thông tin sản phẩm được cung cấp
            2. Cá nhân hóa câu trả lời dựa trên thông tin khách hàng (nếu có)
            3. Giữ giọng điệu thân thiện, chuyên nghiệp và hữu ích
            4. Nếu không có thông tin phù hợp, hãy thành thật thừa nhận và đề xuất cách khác"""

            user_prompt = f"""
            Câu hỏi của khách hàng: {question}
            Thông tin liên quan:
            {context}
            Hãy trả lời câu hỏi một cách chi tiết, chính xác và thân thiện bằng tiếng Việt."""

            response = self.client.models.generate_content(
                model='gemini-2.0-flash-001',
                contents=[
                    {'role': 'system', 'parts': [system_prompt]},
                    {'role': 'user', 'parts': [user_prompt]}
                ],
                config=types.GenerateContentConfig(
                    safety_settings=[
                        types.SafetySetting(category='HARM_CATEGORY_HATE_SPEECH', threshold='BLOCK_ONLY_HIGH'),
                        types.SafetySetting(category='HARM_CATEGORY_DANGEROUS_CONTENT', threshold='BLOCK_ONLY_HIGH')
                    ],
                    temperature=temperature_score,
                    max_output_tokens=1000
                )
            )

            if response and hasattr(response, 'text'):
                answer = response.text.strip()
            else:
                answer = "Xin lỗi, tôi không thể trả lời câu hỏi này lúc này."

            if visitor_id and session_id:
                interaction = {
                    'timestamp': datetime.now(timezone.utc).isoformat(),
                    'question': question,
                    'answer': answer,
                    'relevant_products': [doc['product_id'] for doc in relevant_docs]
                }
                await self.update_user_memory(visitor_id, session_id, interaction)

            return {
                'answer': answer,
                'relevant_documents': relevant_docs,
                'context_used': bool(context),
                'timestamp': datetime.now(timezone.utc).isoformat()
            }
        except Exception as error:
            logger.error(f"Error in ask_question: {error}")
            return {
                'answer': f"Tôi chưa có thông tin để trả lời câu hỏi này. Bạn có thể tìm kiếm thêm tại https://www.google.com/search?q={question}",
                'relevant_documents': [],
                'context_used': False,
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'error': str(error)
            }

# Utilities
async def initialize_rag_system() -> VietnameseRAGSystem:
    rag_system = VietnameseRAGSystem()
    await rag_system.initialize_db_pool()
    return rag_system

async def batch_add_products(rag_system: VietnameseRAGSystem, products: List[Dict]):
    tasks = []
    for product in products:
        task = rag_system.add_product_to_knowledge_base(
            product['product_id'], product['name'], product['specs'], product['content']
        )
        tasks.append(task)
    results = await asyncio.gather(*tasks, return_exceptions=True)
    return results

async def main():
    rag_system = await initialize_rag_system()

    sample_products = [
        {
            'product_id': 'laptop-001',
            'name': 'Laptop Dell XPS 13',
            'specs': {
                'cpu': 'Intel Core i7-1165G7',
                'ram': '16GB LPDDR4',
                'storage': '512GB SSD',
                'display': '13.3 inch FHD+',
                'price': '25000000'
            },
            'content': 'Laptop Dell XPS 13 với thiết kế mỏng nhẹ, hiệu năng mạnh mẽ. Phù hợp cho công việc văn phòng và sáng tạo nội dung.'
        }
    ]
    await batch_add_products(rag_system, sample_products)

    result = await rag_system.ask_question(
        question="Tôi cần một chiếc laptop để làm việc văn phòng, có thể tư vấn không?",
        visitor_id="user_123",
        session_id="session_456"
    )

    print("Answer:", result['answer'])
    print("Relevant docs:", len(result['relevant_documents']))

    await rag_system.close_db_pool()

if __name__ == "__main__":
    asyncio.run(main())
