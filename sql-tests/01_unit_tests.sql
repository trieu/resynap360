-- Clear existing attributes
DELETE FROM cdp_profile_attributes;

-- Insert sample identity resolution attributes
-- Insert sample identity resolution attributes
INSERT INTO cdp_profile_attributes (
    id, name,  attribute_internal_code, data_type,
    is_identity_resolution, matching_rule, matching_threshold,
    consolidation_rule, status, is_index
) VALUES
(1, 'email', 'email', 'TEXT', TRUE, 'exact', NULL, 'non_null', 'ACTIVE', TRUE),
(2, 'phone_number','phone_number', 'TEXT', TRUE, 'exact', NULL, 'non_null', 'ACTIVE', TRUE),
(3,'first_name',  'first_name', 'TEXT', FALSE, 'fuzzy_dmetaphone', NULL, 'most_recent', 'ACTIVE', FALSE),
(4,'last_name', 'last_name', 'TEXT', FALSE, 'fuzzy_trgm', 0.7, 'most_recent', 'ACTIVE', FALSE),
(5,'zalo_user_id', 'zalo_user_id', 'TEXT', TRUE, 'exact',NULL, 'prefer_master', 'ACTIVE', TRUE),
(6,'web_visitor_id', 'web_visitor_id', 'TEXT', TRUE, 'exact',NULL, 'most_recent', 'ACTIVE', TRUE),
(7,'crm_id', 'crm_id', 'TEXT', TRUE, 'exact',NULL, 'prefer_master', 'ACTIVE', TRUE),
;


-- Clear existing raw profiles
DELETE FROM cdp_profile_links;
DELETE FROM cdp_raw_profiles_stage;
DELETE FROM cdp_master_profiles;

-- Insert sample raw profiles
INSERT INTO cdp_raw_profiles_stage (
    raw_profile_id, first_name, last_name, email, phone_number,
    address_line1, city, state, zip_code, source_system, processed_at
) VALUES
(gen_random_uuid(), 'John', 'Smith', 'john@example.com', '1234567890', '123 Elm St', 'New York', 'NY', '10001', 'SystemA', NULL),
(gen_random_uuid(), 'Jon', 'Smyth', 'john@example.com', NULL, '123 Elm Street', 'New York', 'NY', '10001', 'SystemB', NULL),
(gen_random_uuid(), 'Jane', 'Doe', 'jane.d@example.com', '5551234567', '456 Oak Ave', 'Los Angeles', 'CA', '90001', 'SystemA', NULL),
(gen_random_uuid(), 'Janet', 'Do', 'jane.d@example.com', '5551234567', '456 Oak Ave', 'Los Angeles', 'CA', '90001', 'SystemB', NULL),
(gen_random_uuid(), 'Mike', 'Tyson', NULL, '8889990000', '789 Pine Rd', 'Chicago', 'IL', '60601', 'SystemC', NULL);

INSERT INTO cdp_raw_profiles_stage (
    raw_profile_id, first_name, last_name, email, phone_number,
    address_line1, city, state, zalo_user_id, source_system, processed_at
) VALUES
(gen_random_uuid(), 'Trieu', 'Nguyen', '', '09031229', 'Q6', '', 'Vietnam', '456', 'Zalo', NULL);