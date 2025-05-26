import os
import glob
import logging
from dotenv import load_dotenv # Used for local testing
# import psycopg2 # Uncomment if using psycopg2 with a Lambda Layer
# from psycopg2 import sql, Error # Uncomment if using psycopg2
import pg8000 # Use pg8000 for simpler Lambda deployment

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger()
logger.setLevel(logging.INFO) # Ensure Lambda logs INFO level messages

# --- Load environment variables from .env file if running locally ---
# In AWS Lambda, these environment variables will be set directly
# in the Lambda configuration, not loaded from a .env file.
# This call is primarily for making local testing easier.
if os.path.exists('.env'):
    load_dotenv()
    logger.info("Loaded environment variables from .env file for local testing.")
# -------------------------------------------------------------------


# Update the Executor class to use pg8000
class PostgreSQLExecutor:
    """Handles connection and execution of SQL scripts against a PostgreSQL database using pg8000."""

    def __init__(self, db_config):
        """
        Initializes the database executor with connection parameters.

        Args:
            db_config (dict): A dictionary containing database connection details
                              (host, database, user, password, port).
        """
        self.db_config = db_config
        self.conn = None
        self.cursor = None

    def connect(self):
        """Establishes a connection to the PostgreSQL database using pg8000."""
        try:
            logger.info("Connecting to the PostgreSQL database using pg8000...")
            # pg8000.connect takes parameters as keywords
            self.conn = pg8000.dbapi.connect(
                host=self.db_config.get('host'),
                database=self.db_config.get('database'),
                user=self.db_config.get('user'),
                password=self.db_config.get('password'),
                port=self.db_config.get('port', 5432) # Default port 5432
            )
            # pg8000 connections are implicitly in a transaction, autocommit is False by default
            self.cursor = self.conn.cursor()
            logger.info("Database connection successful with pg8000.")
        except Exception as e: # pg8000 uses standard Python exceptions, not psycopg2.Error
            logger.error(f"Error connecting to the database using pg8000: {e}")
            raise # Re-raise the exception to stop execution

    def execute_script(self, script_content: str, script_name: str):
        """
        Executes a single SQL script using pg8000.

        Args:
            script_content (str): The content of the SQL script.
            script_name (str): The name of the script file (for logging).

        Returns:
            bool: True if execution was successful, False otherwise.
        """
        if not self.conn: # Check if connection is established
            logger.error(f"Database connection is not open. Cannot execute script: {script_name}")
            return False
        if self.cursor is None:
             logger.error(f"Database cursor is not available. Cannot execute script: {script_name}")
             return False

        logger.info(f"Executing script: {script_name}")
        try:
            # pg8000's cursor.execute can handle multiple statements
            self.cursor.execute(script_content)
            self.conn.commit() # Commit the transaction for this script
            logger.info(f"Successfully executed and committed: {script_name}")
            return True
        except Exception as e: # Catch any execution errors
            self.conn.rollback() # Rollback the transaction
            logger.error(f"Error executing script {script_name}: {e}")
            logger.error("Transaction rolled back.")
            return False # Indicate failure

    def close(self):
        """Closes the database cursor and connection."""
        if self.cursor:
            self.cursor.close()
            logger.info("Cursor closed.")
        if self.conn:
            self.conn.close()
            logger.info("Database connection closed.")

    def __enter__(self):
        """Context manager entry: Connects to the database."""
        self.connect()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit: Closes the database connection."""
        self.close()
        # Returning False allows exceptions to propagate
        return False


class SQLScriptRunner:
    """Manages locating and running SQL scripts in order."""

    def __init__(self, script_dir: str, db_executor: PostgreSQLExecutor):
        """
        Initializes the script runner.

        Args:
            script_dir (str): The directory containing the SQL scripts.
            db_executor (PostgreSQLExecutor): An instance of the database executor.
        """
        # In Lambda, the deployment package is typically under /var/task
        # However, relative paths like 'sql-scripts' usually work if the folder
        # is at the root of your zip file. Using abspath is safer if structure is complex.
        # For a simple structure (sql-scripts folder at root), just 'sql-scripts' is fine.
        self.script_dir = script_dir
        self.db_executor = db_executor

    def get_scripts(self) -> list:
        """
        Finds and returns a sorted list of SQL script file paths.

        Returns:
            list: A list of absolute paths to the SQL files, sorted alphabetically.
        """
        # Ensure the directory exists within the Lambda environment
        if not os.path.isdir(self.script_dir):
             logger.error(f"Script directory '{self.script_dir}' not found in Lambda package.")
             return [] # Return empty list if directory doesn't exist

        search_pattern = os.path.join(self.script_dir, "*.sql")
        script_files = sorted(glob.glob(search_pattern))
        logger.info(f"Found {len(script_files)} SQL scripts in '{self.script_dir}'.")
        for script in script_files:
            logger.debug(f"  - {os.path.basename(script)}")
        return script_files

    def run_all_scripts(self):
        """Runs all found SQL scripts in order using the database executor."""
        script_files = self.get_scripts()
        if not script_files:
            logger.warning("No SQL script files found or script directory missing. Exiting.")
            return False # Indicate failure if no scripts found

        logger.info("Starting execution of all SQL scripts.")
        success_count = 0
        failed_scripts = []
        execution_successful = True # Flag to indicate if all scripts ran without error (based on our continue-on-error logic)

        for script_path in script_files:
            script_name = os.path.basename(script_path)
            try:
                # Ensure file is read with utf-8 encoding
                with open(script_path, 'r', encoding='utf-8') as f:
                    script_content = f.read()

                if self.db_executor.execute_script(script_content, script_name):
                    success_count += 1
                else:
                    failed_scripts.append(script_name)
                    execution_successful = False # Mark as failed if any script fails
                    # If you want to stop on first error, uncomment this:
                    # logger.error("Stopping execution due to script failure.")
                    # break

            except FileNotFoundError:
                logger.error(f"Script file not found: {script_name}")
                failed_scripts.append(script_name)
                execution_successful = False
            except IOError as e:
                logger.error(f"Error reading script file {script_name}: {e}")
                failed_scripts.append(script_name)
                execution_successful = False
            except Exception as e:
                 logger.error(f"An unexpected error occurred processing {script_name}: {e}")
                 failed_scripts.append(script_name)
                 execution_successful = False


        logger.info("-" * 30)
        logger.info("SQL script execution summary:")
        logger.info(f"Total scripts found: {len(script_files)}")
        logger.info(f"Scripts successfully executed: {success_count}")
        if failed_scripts:
            logger.warning(f"Scripts failed ({len(failed_scripts)}): {', '.join(failed_scripts)}")
        else:
            logger.info("All scripts executed successfully.")
        logger.info("-" * 30)

        return execution_successful # Return overall success status


# --- Lambda Handler Function ---
def lambda_handler(event, context):
    """
    AWS Lambda handler function to execute SQL scripts.

    Args:
        event: The event dict (usually not used for this type of trigger).
        context: The context object (provides info about the invocation, function, etc.).

    Returns:
        dict: A dictionary with statusCode and a body message.
    """
    SCRIPT_DIRECTORY = "sql-scripts" # Relative path within your deployment package

    try:
        # 1. Load database configuration from Environment Variables
        # In Lambda, os.getenv reads directly from the function's configuration
        db_configuration = {
            "host": os.getenv("DB_HOST"),
            "database": os.getenv("DB_DATABASE"),
            "user": os.getenv("DB_USER"),
            "password": os.getenv("DB_PASSWORD"),
            # Get port and convert to int, default to 5432 if not set or invalid
            "port": int(os.getenv("DB_PORT", 5432))
        }

        # Basic check to ensure essential variables are loaded
        if not all([db_configuration['host'], db_configuration['database'], db_configuration['user'], db_configuration['password']]):
             logger.error("Missing one or more essential database environment variables (DB_HOST, DB_DATABASE, DB_USER, DB_PASSWORD).")
             # Return a client error status code
             return {
                 'statusCode': 400,
                 'body': 'Configuration error: Missing database environment variables.'
             }

        # 2. Use the context manager for the database connection
        # The 'with' statement ensures connection is closed automatically
        with PostgreSQLExecutor(db_configuration) as db_executor:
            # 3. Initialize the script runner
            runner = SQLScriptRunner(SCRIPT_DIRECTORY, db_executor)

            # 4. Run all scripts
            all_scripts_executed_successfully = runner.run_all_scripts()

        # Determine final response based on overall script execution status
        if all_scripts_executed_successfully:
            return {
                'statusCode': 200,
                'body': 'All SQL scripts executed successfully.'
            }
        else:
            # Return a server error status code if any script failed
            return {
                'statusCode': 500,
                'body': 'Some SQL scripts failed during execution. Check logs for details.'
            }

    except ValueError as e:
         logger.error(f"Configuration error: {e}")
         return {
             'statusCode': 400,
             'body': f'Configuration error: {e}'
         }
    except Exception as e:
        # Catch any unexpected errors during the process (e.g., connection errors)
        logger.error(f"An unexpected error occurred during Lambda execution: {e}")
        return {
            'statusCode': 500,
            'body': f'An internal server error occurred: {e}'
        }