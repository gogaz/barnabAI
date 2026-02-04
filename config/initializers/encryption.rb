# frozen_string_literal: true

# ActiveRecord::Encryption configuration
# This encrypts sensitive data at rest in the database
# 
# Keys can be set via:
# - Rails credentials (recommended for production)
# - Environment variables (for development/testing)
# - Fallback to secret_key_base (works but not recommended for production)

# Primary key - used to encrypt/decrypt data
Rails.application.config.active_record.encryption.primary_key = 
  Rails.application.credentials.dig(:active_record_encryption, :primary_key) ||
  ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"] ||
  Rails.application.secret_key_base[0..31]

# Deterministic key - used for deterministic encryption (searchable encrypted fields)
Rails.application.config.active_record.encryption.deterministic_key = 
  Rails.application.credentials.dig(:active_record_encryption, :deterministic_key) ||
  ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"] ||
  Rails.application.secret_key_base[32..63]

# Key derivation salt - used for key derivation
Rails.application.config.active_record.encryption.key_derivation_salt = 
  Rails.application.credentials.dig(:active_record_encryption, :key_derivation_salt) ||
  ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"] ||
  Rails.application.secret_key_base[64..95]

# Log warnings in production if using fallback keys
if Rails.env.production?
  unless Rails.application.credentials.dig(:active_record_encryption, :primary_key) || ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
    Rails.logger.warn "ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY not set, using secret_key_base fallback (not recommended for production)"
  end
end
