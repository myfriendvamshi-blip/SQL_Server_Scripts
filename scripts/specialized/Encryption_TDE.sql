/* Validation: PARSED-CI + LAB-REQUIRED | Read-only; never outputs private keys or passwords */
SET NOCOUNT ON;
SELECT d.name,d.is_encrypted,dek.encryption_state,dek.encryption_state_desc,
       dek.percent_complete,dek.key_algorithm,dek.key_length,dek.encryptor_type,
       dek.regenerate_date,dek.modify_date,dek.set_date,dek.opened_date
FROM sys.databases AS d
LEFT JOIN sys.dm_database_encryption_keys AS dek ON dek.database_id=d.database_id
ORDER BY d.database_id;

SELECT name,pvt_key_encryption_type_desc,subject,start_date,expiry_date,
       thumbprint,DATALENGTH(pvt_key_encryption_type_desc) AS metadata_length
FROM master.sys.certificates
WHERE name NOT LIKE '##%'
ORDER BY name;

SELECT name,key_length,algorithm_desc,provider_type,cryptographic_provider_guid,
       key_thumbprint,create_date,modify_date
FROM sys.asymmetric_keys
ORDER BY name;

SELECT name,key_length,algorithm_desc,key_guid,create_date,modify_date
FROM sys.symmetric_keys
WHERE name<>N'##MS_DatabaseMasterKey##'
ORDER BY name;
