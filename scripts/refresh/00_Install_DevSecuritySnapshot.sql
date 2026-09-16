/*
  Installs the DEV security snapshot engine in DBA_Admin.
  Run once on the DEV SQL Server as sysadmin.

  Design rules:
  - Snapshot data is stored outside the database that will be overwritten.
  - Unsupported identity types fail capture instead of being silently omitted.
  - Apply removes restored explicit permissions, memberships, users and custom roles
    before replaying the DEV snapshot in one transaction.
  - The target stays SINGLE_USER if replay or validation fails.
*/
USE master;
SET NOCOUNT ON;
SET XACT_ABORT ON;

IF DB_ID(N'DBA_Admin') IS NULL
BEGIN
    CREATE DATABASE DBA_Admin;
END;
GO

USE DBA_Admin;
GO

IF OBJECT_ID(N'dbo.DevSecuritySnapshot', N'U') IS NULL
CREATE TABLE dbo.DevSecuritySnapshot
(
    snapshot_id             uniqueidentifier NOT NULL CONSTRAINT PK_DevSecuritySnapshot PRIMARY KEY,
    database_name           sysname          NOT NULL,
    source_server           sysname          NOT NULL,
    database_owner          sysname          NOT NULL,
    captured_at_utc         datetime2(0)     NOT NULL,
    captured_by             sysname          NOT NULL,
    status                  varchar(20)      NOT NULL,
    principal_count         int              NOT NULL,
    role_membership_count   int              NOT NULL,
    permission_count        int              NOT NULL,
    schema_owner_count      int              NOT NULL,
    applied_database        sysname          NULL,
    applied_at_utc          datetime2(0)     NULL,
    error_message           nvarchar(2048)   NULL
);

IF OBJECT_ID(N'dbo.DevSecuritySnapshotPrincipal', N'U') IS NULL
CREATE TABLE dbo.DevSecuritySnapshotPrincipal
(
    snapshot_id             uniqueidentifier NOT NULL,
    principal_name          sysname          NOT NULL,
    principal_type          char(1)          NOT NULL,
    authentication_type     int              NOT NULL,
    sid                     varbinary(85)    NULL,
    default_schema_name     sysname          NULL,
    mapped_login_name       sysname          NULL,
    CONSTRAINT PK_DevSecuritySnapshotPrincipal PRIMARY KEY(snapshot_id, principal_name),
    CONSTRAINT FK_DevSecuritySnapshotPrincipal_Header FOREIGN KEY(snapshot_id)
        REFERENCES dbo.DevSecuritySnapshot(snapshot_id) ON DELETE CASCADE
);

IF OBJECT_ID(N'dbo.DevSecuritySnapshotCommand', N'U') IS NULL
CREATE TABLE dbo.DevSecuritySnapshotCommand
(
    snapshot_id             uniqueidentifier NOT NULL,
    command_order           int              NOT NULL,
    command_type            varchar(30)      NOT NULL,
    principal_name          sysname          NULL,
    command_text            nvarchar(max)    NOT NULL,
    CONSTRAINT PK_DevSecuritySnapshotCommand PRIMARY KEY(snapshot_id, command_order),
    CONSTRAINT FK_DevSecuritySnapshotCommand_Header FOREIGN KEY(snapshot_id)
        REFERENCES dbo.DevSecuritySnapshot(snapshot_id) ON DELETE CASCADE
);
GO

CREATE OR ALTER PROCEDURE dbo.usp_CaptureDevDatabaseSecurity
    @DatabaseName sysname,
    @SnapshotId uniqueidentifier = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF IS_SRVROLEMEMBER(N'sysadmin') <> 1
        THROW 51000, 'sysadmin is required to capture complete database security metadata.', 1;
    IF DB_ID(@DatabaseName) IS NULL
        THROW 51001, 'The DEV database does not exist.', 1;
    IF DB_ID(@DatabaseName) <= 4
        THROW 51002, 'System databases are not valid refresh targets.', 1;
    IF EXISTS (SELECT 1 FROM sys.databases WHERE name=@DatabaseName AND state_desc<>N'ONLINE')
        THROW 51003, 'The DEV database must be ONLINE.', 1;

    DECLARE @DatabaseOwner sysname =
      (SELECT SUSER_SNAME(owner_sid) FROM sys.databases WHERE name=@DatabaseName);
    IF @DatabaseOwner IS NULL OR SUSER_ID(@DatabaseOwner) IS NULL
        THROW 51004, 'The current DEV database owner cannot be resolved to a server login.', 1;

    DECLARE @Unsupported int=0, @MissingLogins int=0, @UnsupportedPermissions int=0;
    DECLARE @Preflight nvarchar(max)=N'
USE '+QUOTENAME(@DatabaseName)+N';
SELECT @UnsupportedOut=COUNT(*)
FROM sys.database_principals AS dp
WHERE dp.principal_id>4 AND dp.is_fixed_role=0
  AND
  (
      dp.type NOT IN (''S'',''U'',''G'',''E'',''X'',''R'')
      OR (dp.type=''S'' AND dp.authentication_type NOT IN (0,1))
  );

SELECT @MissingLoginsOut=COUNT(*)
FROM sys.database_principals AS dp
LEFT JOIN master.sys.server_principals AS sp ON sp.sid=dp.sid
WHERE dp.principal_id>4 AND dp.is_fixed_role=0
  AND dp.type IN (''S'',''U'',''G'') AND dp.authentication_type=1
  AND sp.principal_id IS NULL;

SELECT @UnsupportedPermissionsOut=COUNT(*)
FROM sys.database_permissions
WHERE NOT (class=1 AND major_id<0)
  AND class NOT IN (0,1,3,4,5,6,10,15,16,17,18,19,23,24,25,26,29,31,32,34);';
    EXEC sys.sp_executesql @Preflight,
      N'@UnsupportedOut int OUTPUT,@MissingLoginsOut int OUTPUT,@UnsupportedPermissionsOut int OUTPUT',
      @UnsupportedOut=@Unsupported OUTPUT,
      @MissingLoginsOut=@MissingLogins OUTPUT,
      @UnsupportedPermissionsOut=@UnsupportedPermissions OUTPUT;

    IF @Unsupported>0
        THROW 51005, 'Unsupported DEV principals found. Contained SQL users, application roles, and certificate/asymmetric-key users cannot be recreated without unavailable secrets or keys.', 1;
    IF @MissingLogins>0
        THROW 51006, 'One or more DEV users map to a server login SID that is missing on this DEV instance.', 1;
    IF @UnsupportedPermissions>0
        THROW 51007, 'An unsupported database permission class was found. Capture stopped to prevent silent permission loss.', 1;

    SET @SnapshotId=COALESCE(@SnapshotId,NEWID());
    IF EXISTS (SELECT 1 FROM dbo.DevSecuritySnapshot WHERE snapshot_id=@SnapshotId)
        THROW 51008, 'The supplied SnapshotId already exists.', 1;

    INSERT dbo.DevSecuritySnapshot
    (
      snapshot_id,database_name,source_server,database_owner,captured_at_utc,captured_by,status,
      principal_count,role_membership_count,permission_count,schema_owner_count
    )
    VALUES
    (@SnapshotId,@DatabaseName,@@SERVERNAME,@DatabaseOwner,SYSUTCDATETIME(),ORIGINAL_LOGIN(),N'CAPTURING',0,0,0,0);

    DECLARE @Sql nvarchar(max)=N'
USE '+QUOTENAME(@DatabaseName)+N';

INSERT DBA_Admin.dbo.DevSecuritySnapshotPrincipal
 (snapshot_id,principal_name,principal_type,authentication_type,sid,default_schema_name,mapped_login_name)
SELECT @SnapshotId,dp.name,dp.type,dp.authentication_type,dp.sid,dp.default_schema_name,sp.name
FROM sys.database_principals AS dp
LEFT JOIN master.sys.server_principals AS sp ON sp.sid=dp.sid
WHERE dp.principal_id>4 AND dp.is_fixed_role=0;

/* Users mapped to DEV logins. The database user name may differ from the login name. */
INSERT DBA_Admin.dbo.DevSecuritySnapshotCommand
 (snapshot_id,command_order,command_type,principal_name,command_text)
SELECT @SnapshotId,100000+ROW_NUMBER() OVER(ORDER BY dp.name),''CREATE_USER'',dp.name,
       N''CREATE USER ''+QUOTENAME(dp.name)+N'' FOR LOGIN ''+QUOTENAME(sp.name)
       +CASE WHEN dp.default_schema_name IS NULL THEN N''''
             ELSE N'' WITH DEFAULT_SCHEMA = ''+QUOTENAME(dp.default_schema_name) END+N'';''
FROM sys.database_principals AS dp
JOIN master.sys.server_principals AS sp ON sp.sid=dp.sid
WHERE dp.principal_id>4 AND dp.is_fixed_role=0
  AND dp.type IN (''S'',''U'',''G'') AND dp.authentication_type=1;

/* Users without login contain no password and can be recreated exactly. */
INSERT DBA_Admin.dbo.DevSecuritySnapshotCommand
 (snapshot_id,command_order,command_type,principal_name,command_text)
SELECT @SnapshotId,120000+ROW_NUMBER() OVER(ORDER BY dp.name),''CREATE_USER'',dp.name,
       N''CREATE USER ''+QUOTENAME(dp.name)+N'' WITHOUT LOGIN''
       +CASE WHEN dp.default_schema_name IS NULL THEN N''''
             ELSE N'' WITH DEFAULT_SCHEMA = ''+QUOTENAME(dp.default_schema_name) END+N'';''
FROM sys.database_principals AS dp
WHERE dp.principal_id>4 AND dp.is_fixed_role=0
  AND dp.type=''S'' AND dp.authentication_type=0;

/* Microsoft Entra principals are replayed by name; the DEV server must have Entra configured. */
INSERT DBA_Admin.dbo.DevSecuritySnapshotCommand
 (snapshot_id,command_order,command_type,principal_name,command_text)
SELECT @SnapshotId,140000+ROW_NUMBER() OVER(ORDER BY dp.name),''CREATE_EXTERNAL_USER'',dp.name,
       N''CREATE USER ''+QUOTENAME(dp.name)+N'' FROM EXTERNAL PROVIDER''
       +CASE WHEN dp.default_schema_name IS NULL THEN N''''
             ELSE N'' WITH DEFAULT_SCHEMA = ''+QUOTENAME(dp.default_schema_name) END+N'';''
FROM sys.database_principals AS dp
WHERE dp.principal_id>4 AND dp.is_fixed_role=0 AND dp.type IN (''E'',''X'');

INSERT DBA_Admin.dbo.DevSecuritySnapshotCommand
 (snapshot_id,command_order,command_type,principal_name,command_text)
SELECT @SnapshotId,200000+ROW_NUMBER() OVER(ORDER BY dp.name),''CREATE_ROLE'',dp.name,
       N''CREATE ROLE ''+QUOTENAME(dp.name)+N'' AUTHORIZATION [dbo];''
FROM sys.database_principals AS dp
WHERE dp.principal_id>4 AND dp.is_fixed_role=0 AND dp.type=''R'';

INSERT DBA_Admin.dbo.DevSecuritySnapshotCommand
 (snapshot_id,command_order,command_type,principal_name,command_text)
SELECT @SnapshotId,300000+ROW_NUMBER() OVER(ORDER BY dp.name),''ROLE_OWNER'',dp.name,
       N''ALTER AUTHORIZATION ON ROLE::''+QUOTENAME(dp.name)+N'' TO ''+QUOTENAME(ownerp.name)+N'';''
FROM sys.database_principals AS dp
JOIN sys.database_principals AS ownerp ON ownerp.principal_id=dp.owning_principal_id
WHERE dp.principal_id>4 AND dp.is_fixed_role=0 AND dp.type=''R'' AND ownerp.name<>N''dbo'';

INSERT DBA_Admin.dbo.DevSecuritySnapshotCommand
 (snapshot_id,command_order,command_type,principal_name,command_text)
SELECT @SnapshotId,400000+ROW_NUMBER() OVER(ORDER BY s.name),''SCHEMA_OWNER'',ownerp.name,
       N''ALTER AUTHORIZATION ON SCHEMA::''+QUOTENAME(s.name)+N'' TO ''+QUOTENAME(ownerp.name)+N'';''
FROM sys.schemas AS s
JOIN sys.database_principals AS ownerp ON ownerp.principal_id=s.principal_id
WHERE s.schema_id>4;

INSERT DBA_Admin.dbo.DevSecuritySnapshotCommand
 (snapshot_id,command_order,command_type,principal_name,command_text)
SELECT @SnapshotId,450000+ROW_NUMBER() OVER(ORDER BY s.name,o.name),''OBJECT_OWNER'',ownerp.name,
       N''ALTER AUTHORIZATION ON OBJECT::''+QUOTENAME(s.name)+N''.''+QUOTENAME(o.name)
       +N'' TO ''+QUOTENAME(ownerp.name)+N'';''
FROM sys.objects AS o
JOIN sys.schemas AS s ON s.schema_id=o.schema_id
JOIN sys.database_principals AS ownerp ON ownerp.principal_id=o.principal_id
WHERE o.is_ms_shipped=0 AND o.principal_id IS NOT NULL;

INSERT DBA_Admin.dbo.DevSecuritySnapshotCommand
 (snapshot_id,command_order,command_type,principal_name,command_text)
SELECT @SnapshotId,500000+ROW_NUMBER() OVER(ORDER BY rolep.name,memberp.name),''ROLE_MEMBER'',memberp.name,
       N''ALTER ROLE ''+QUOTENAME(rolep.name)+N'' ADD MEMBER ''+QUOTENAME(memberp.name)+N'';''
FROM sys.database_role_members AS rm
JOIN sys.database_principals AS rolep ON rolep.principal_id=rm.role_principal_id
JOIN sys.database_principals AS memberp ON memberp.principal_id=rm.member_principal_id
WHERE memberp.name<>N''dbo'';

;WITH PermissionSource AS
(
 SELECT p.*,grantee.name COLLATE DATABASE_DEFAULT AS grantee_name,grantor.name COLLATE DATABASE_DEFAULT AS grantor_name,
        targetp.name COLLATE DATABASE_DEFAULT AS target_principal_name,targetp.type AS target_principal_type,
        os.name COLLATE DATABASE_DEFAULT AS object_schema_name,o.name COLLATE DATABASE_DEFAULT AS object_name,
        c.name COLLATE DATABASE_DEFAULT AS column_name,ss.name COLLATE DATABASE_DEFAULT AS schema_name,
        a.name COLLATE DATABASE_DEFAULT AS assembly_name,ts.name COLLATE DATABASE_DEFAULT AS type_schema_name,
        t.name COLLATE DATABASE_DEFAULT AS type_name,xs.name COLLATE DATABASE_DEFAULT AS xml_schema_name,
        x.name COLLATE DATABASE_DEFAULT AS xml_name,mt.name COLLATE DATABASE_DEFAULT AS message_type_name,
        sc.name COLLATE DATABASE_DEFAULT AS contract_name,svc.name COLLATE DATABASE_DEFAULT AS service_name,
        rsb.name COLLATE DATABASE_DEFAULT AS remote_binding_name,r.name COLLATE DATABASE_DEFAULT AS route_name,
        fc.name COLLATE DATABASE_DEFAULT AS fulltext_catalog_name,sk.name COLLATE DATABASE_DEFAULT AS symmetric_key_name,
        cert.name COLLATE DATABASE_DEFAULT AS certificate_name,ak.name COLLATE DATABASE_DEFAULT AS asymmetric_key_name,
        fsl.name COLLATE DATABASE_DEFAULT AS stoplist_name,spl.name COLLATE DATABASE_DEFAULT AS property_list_name,
        dsc.name COLLATE DATABASE_DEFAULT AS credential_name,el.language COLLATE DATABASE_DEFAULT AS external_language_name
 FROM sys.database_permissions AS p
 JOIN sys.database_principals AS grantee ON grantee.principal_id=p.grantee_principal_id
 JOIN sys.database_principals AS grantor ON grantor.principal_id=p.grantor_principal_id
 LEFT JOIN sys.database_principals AS targetp ON p.class=4 AND targetp.principal_id=p.major_id
 LEFT JOIN sys.objects AS o ON p.class=1 AND o.object_id=p.major_id
 LEFT JOIN sys.schemas AS os ON os.schema_id=o.schema_id
 LEFT JOIN sys.columns AS c ON p.class=1 AND c.object_id=p.major_id AND c.column_id=p.minor_id
 LEFT JOIN sys.schemas AS ss ON p.class=3 AND ss.schema_id=p.major_id
 LEFT JOIN sys.assemblies AS a ON p.class=5 AND a.assembly_id=p.major_id
 LEFT JOIN sys.types AS t ON p.class=6 AND t.user_type_id=p.major_id
 LEFT JOIN sys.schemas AS ts ON ts.schema_id=t.schema_id
 LEFT JOIN sys.xml_schema_collections AS x ON p.class=10 AND x.xml_collection_id=p.major_id
 LEFT JOIN sys.schemas AS xs ON xs.schema_id=x.schema_id
 LEFT JOIN sys.service_message_types AS mt ON p.class=15 AND mt.message_type_id=p.major_id
 LEFT JOIN sys.service_contracts AS sc ON p.class=16 AND sc.service_contract_id=p.major_id
 LEFT JOIN sys.services AS svc ON p.class=17 AND svc.service_id=p.major_id
 LEFT JOIN sys.remote_service_bindings AS rsb ON p.class=18 AND rsb.remote_service_binding_id=p.major_id
 LEFT JOIN sys.routes AS r ON p.class=19 AND r.route_id=p.major_id
 LEFT JOIN sys.fulltext_catalogs AS fc ON p.class=23 AND fc.fulltext_catalog_id=p.major_id
 LEFT JOIN sys.symmetric_keys AS sk ON p.class=24 AND sk.symmetric_key_id=p.major_id
 LEFT JOIN sys.certificates AS cert ON p.class=25 AND cert.certificate_id=p.major_id
 LEFT JOIN sys.asymmetric_keys AS ak ON p.class=26 AND ak.asymmetric_key_id=p.major_id
 LEFT JOIN sys.fulltext_stoplists AS fsl ON p.class=29 AND fsl.stoplist_id=p.major_id
 LEFT JOIN sys.registered_search_property_lists AS spl ON p.class=31 AND spl.property_list_id=p.major_id
 LEFT JOIN sys.database_scoped_credentials AS dsc ON p.class=32 AND dsc.credential_id=p.major_id
 LEFT JOIN sys.external_languages AS el ON p.class=34 AND el.external_language_id=p.major_id
 WHERE grantee.name<>N''dbo'' AND NOT (p.class=1 AND p.major_id<0)
)
SELECT *,
   CASE class
    WHEN 0 THEN N''''
    WHEN 1 THEN N'' ON OBJECT::''+QUOTENAME(object_schema_name)+N''.''+QUOTENAME(object_name)
                    +CASE WHEN minor_id=0 THEN N'''' ELSE N'' (''+QUOTENAME(column_name)+N'')'' END
    WHEN 3 THEN N'' ON SCHEMA::''+QUOTENAME(schema_name)
    WHEN 4 THEN N'' ON ''+CASE WHEN target_principal_type=''R'' THEN N''ROLE::'' ELSE N''USER::'' END+QUOTENAME(target_principal_name)
    WHEN 5 THEN N'' ON ASSEMBLY::''+QUOTENAME(assembly_name)
    WHEN 6 THEN N'' ON TYPE::''+QUOTENAME(type_schema_name)+N''.''+QUOTENAME(type_name)
    WHEN 10 THEN N'' ON XML SCHEMA COLLECTION::''+QUOTENAME(xml_schema_name)+N''.''+QUOTENAME(xml_name)
    WHEN 15 THEN N'' ON MESSAGE TYPE::''+QUOTENAME(message_type_name)
    WHEN 16 THEN N'' ON CONTRACT::''+QUOTENAME(contract_name)
    WHEN 17 THEN N'' ON SERVICE::''+QUOTENAME(service_name)
    WHEN 18 THEN N'' ON REMOTE SERVICE BINDING::''+QUOTENAME(remote_binding_name)
    WHEN 19 THEN N'' ON ROUTE::''+QUOTENAME(route_name)
    WHEN 23 THEN N'' ON FULLTEXT CATALOG::''+QUOTENAME(fulltext_catalog_name)
    WHEN 24 THEN N'' ON SYMMETRIC KEY::''+QUOTENAME(symmetric_key_name)
    WHEN 25 THEN N'' ON CERTIFICATE::''+QUOTENAME(certificate_name)
    WHEN 26 THEN N'' ON ASYMMETRIC KEY::''+QUOTENAME(asymmetric_key_name)
    WHEN 29 THEN N'' ON FULLTEXT STOPLIST::''+QUOTENAME(stoplist_name)
    WHEN 31 THEN N'' ON SEARCH PROPERTY LIST::''+QUOTENAME(property_list_name)
    WHEN 32 THEN N'' ON DATABASE SCOPED CREDENTIAL::''+QUOTENAME(credential_name)
    WHEN 34 THEN N'' ON EXTERNAL LANGUAGE::''+QUOTENAME(external_language_name)
   END AS securable_clause
INTO #CapturedPermissions
FROM PermissionSource;

IF EXISTS
(
 SELECT 1 FROM #CapturedPermissions
 WHERE securable_clause IS NULL OR grantee_name IS NULL OR grantor_name IS NULL
)
BEGIN
 SELECT class,class_desc,major_id,minor_id,permission_name,grantee_name,grantor_name
 FROM #CapturedPermissions
 WHERE securable_clause IS NULL OR grantee_name IS NULL OR grantor_name IS NULL;
 THROW 51009,''A DEV permission securable or principal could not be resolved; capture stopped.'',1;
END;

INSERT DBA_Admin.dbo.DevSecuritySnapshotCommand
 (snapshot_id,command_order,command_type,principal_name,command_text)
SELECT @SnapshotId,
       600000+ROW_NUMBER() OVER(ORDER BY class,major_id,minor_id,grantee_name,permission_name),
       ''PERMISSION'',grantee_name,
       CASE state
        WHEN ''D'' THEN N''DENY ''+permission_name+securable_clause+N'' TO ''+QUOTENAME(grantee_name)+N'' AS ''+QUOTENAME(grantor_name)+N'';''
        WHEN ''R'' THEN N''REVOKE ''+permission_name+securable_clause+N'' FROM ''+QUOTENAME(grantee_name)+N'' AS ''+QUOTENAME(grantor_name)+N'';''
        ELSE N''GRANT ''+permission_name+securable_clause+N'' TO ''+QUOTENAME(grantee_name)
             +CASE WHEN state=''W'' THEN N'' WITH GRANT OPTION'' ELSE N'''' END
             +N'' AS ''+QUOTENAME(grantor_name)+N'';''
       END
FROM #CapturedPermissions;
DROP TABLE #CapturedPermissions;

SELECT @PrincipalCountOut=COUNT(*)
FROM sys.database_principals WHERE principal_id>4 AND is_fixed_role=0;
SELECT @MembershipCountOut=COUNT(*)
FROM sys.database_role_members AS rm
JOIN sys.database_principals AS memberp ON memberp.principal_id=rm.member_principal_id
WHERE memberp.name<>N''dbo'';
SELECT @PermissionCountOut=COUNT(*)
FROM sys.database_permissions AS p
JOIN sys.database_principals AS grantee ON grantee.principal_id=p.grantee_principal_id
WHERE grantee.name<>N''dbo'' AND NOT (p.class=1 AND p.major_id<0);
SELECT @SchemaOwnerCountOut=COUNT(*) FROM sys.schemas WHERE schema_id>4;';

    DECLARE @PrincipalCount int,@MembershipCount int,@PermissionCount int,@SchemaOwnerCount int;
    BEGIN TRY
      EXEC sys.sp_executesql @Sql,
        N'@SnapshotId uniqueidentifier,@PrincipalCountOut int OUTPUT,@MembershipCountOut int OUTPUT,@PermissionCountOut int OUTPUT,@SchemaOwnerCountOut int OUTPUT',
        @SnapshotId=@SnapshotId,
        @PrincipalCountOut=@PrincipalCount OUTPUT,
        @MembershipCountOut=@MembershipCount OUTPUT,
        @PermissionCountOut=@PermissionCount OUTPUT,
        @SchemaOwnerCountOut=@SchemaOwnerCount OUTPUT;

      UPDATE dbo.DevSecuritySnapshot
      SET principal_count=@PrincipalCount,role_membership_count=@MembershipCount,
          permission_count=@PermissionCount,schema_owner_count=@SchemaOwnerCount,status=N'READY'
      WHERE snapshot_id=@SnapshotId;
    END TRY
    BEGIN CATCH
      DELETE dbo.DevSecuritySnapshot WHERE snapshot_id=@SnapshotId;
      THROW;
    END CATCH;

    SELECT * FROM dbo.DevSecuritySnapshot WHERE snapshot_id=@SnapshotId;
    SELECT command_order,command_type,principal_name,command_text
    FROM dbo.DevSecuritySnapshotCommand WHERE snapshot_id=@SnapshotId ORDER BY command_order;
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_ApplyDevDatabaseSecurity
    @DatabaseName sysname,
    @SnapshotId uniqueidentifier
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF IS_SRVROLEMEMBER(N'sysadmin') <> 1
        THROW 51100, 'sysadmin is required for a complete clean-security replay.', 1;
    IF DB_ID(@DatabaseName) IS NULL OR DB_ID(@DatabaseName)<=4
        THROW 51101, 'The restored target database does not exist or is a system database.', 1;
    IF NOT EXISTS (SELECT 1 FROM dbo.DevSecuritySnapshot WHERE snapshot_id=@SnapshotId AND status IN (N'READY',N'FAILED'))
        THROW 51102, 'A READY security snapshot was not found.', 1;

    DECLARE @ExpectedPrincipals int,@ExpectedMemberships int,@ExpectedPermissions int,@Owner sysname;
    SELECT @ExpectedPrincipals=principal_count,@ExpectedMemberships=role_membership_count,
           @ExpectedPermissions=permission_count,@Owner=database_owner
    FROM dbo.DevSecuritySnapshot WHERE snapshot_id=@SnapshotId;
    IF SUSER_ID(@Owner) IS NULL
        THROW 51103, 'The saved DEV database owner login does not exist on this instance.', 1;

    UPDATE dbo.DevSecuritySnapshot
      SET status=N'APPLYING',applied_database=@DatabaseName,applied_at_utc=NULL,error_message=NULL
      WHERE snapshot_id=@SnapshotId;

    DECLARE @Sql nvarchar(max)=N'
USE master;
ALTER DATABASE '+QUOTENAME(@DatabaseName)+N' SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
USE '+QUOTENAME(@DatabaseName)+N';
SET XACT_ABORT ON;
BEGIN TRY
 BEGIN TRAN;

 CREATE TABLE #Work
 (
   work_order int IDENTITY(1,1) PRIMARY KEY,
   command_text nvarchar(max) NOT NULL
 );

 /* Remove all restored explicit permissions, including grants to public/fixed roles. */
 ;WITH PermissionSource AS
 (
  SELECT p.*,grantee.name COLLATE DATABASE_DEFAULT AS grantee_name,targetp.name COLLATE DATABASE_DEFAULT AS target_principal_name,
         targetp.type AS target_principal_type,os.name COLLATE DATABASE_DEFAULT AS object_schema_name,
         o.name COLLATE DATABASE_DEFAULT AS object_name,c.name COLLATE DATABASE_DEFAULT AS column_name,
         ss.name COLLATE DATABASE_DEFAULT AS schema_name,a.name COLLATE DATABASE_DEFAULT AS assembly_name,
         ts.name COLLATE DATABASE_DEFAULT AS type_schema_name,t.name COLLATE DATABASE_DEFAULT AS type_name,
         xs.name COLLATE DATABASE_DEFAULT AS xml_schema_name,x.name COLLATE DATABASE_DEFAULT AS xml_name,
         mt.name COLLATE DATABASE_DEFAULT AS message_type_name,sc.name COLLATE DATABASE_DEFAULT AS contract_name,
         svc.name COLLATE DATABASE_DEFAULT AS service_name,rsb.name COLLATE DATABASE_DEFAULT AS remote_binding_name,
         r.name COLLATE DATABASE_DEFAULT AS route_name,fc.name COLLATE DATABASE_DEFAULT AS fulltext_catalog_name,
         sk.name COLLATE DATABASE_DEFAULT AS symmetric_key_name,cert.name COLLATE DATABASE_DEFAULT AS certificate_name,
         ak.name COLLATE DATABASE_DEFAULT AS asymmetric_key_name,fsl.name COLLATE DATABASE_DEFAULT AS stoplist_name,
         spl.name COLLATE DATABASE_DEFAULT AS property_list_name,dsc.name COLLATE DATABASE_DEFAULT AS credential_name,
         el.language COLLATE DATABASE_DEFAULT AS external_language_name
  FROM sys.database_permissions AS p
  JOIN sys.database_principals AS grantee ON grantee.principal_id=p.grantee_principal_id
  LEFT JOIN sys.database_principals AS targetp ON p.class=4 AND targetp.principal_id=p.major_id
  LEFT JOIN sys.objects AS o ON p.class=1 AND o.object_id=p.major_id
  LEFT JOIN sys.schemas AS os ON os.schema_id=o.schema_id
  LEFT JOIN sys.columns AS c ON p.class=1 AND c.object_id=p.major_id AND c.column_id=p.minor_id
  LEFT JOIN sys.schemas AS ss ON p.class=3 AND ss.schema_id=p.major_id
  LEFT JOIN sys.assemblies AS a ON p.class=5 AND a.assembly_id=p.major_id
  LEFT JOIN sys.types AS t ON p.class=6 AND t.user_type_id=p.major_id
  LEFT JOIN sys.schemas AS ts ON ts.schema_id=t.schema_id
  LEFT JOIN sys.xml_schema_collections AS x ON p.class=10 AND x.xml_collection_id=p.major_id
  LEFT JOIN sys.schemas AS xs ON xs.schema_id=x.schema_id
  LEFT JOIN sys.service_message_types AS mt ON p.class=15 AND mt.message_type_id=p.major_id
  LEFT JOIN sys.service_contracts AS sc ON p.class=16 AND sc.service_contract_id=p.major_id
  LEFT JOIN sys.services AS svc ON p.class=17 AND svc.service_id=p.major_id
  LEFT JOIN sys.remote_service_bindings AS rsb ON p.class=18 AND rsb.remote_service_binding_id=p.major_id
  LEFT JOIN sys.routes AS r ON p.class=19 AND r.route_id=p.major_id
  LEFT JOIN sys.fulltext_catalogs AS fc ON p.class=23 AND fc.fulltext_catalog_id=p.major_id
  LEFT JOIN sys.symmetric_keys AS sk ON p.class=24 AND sk.symmetric_key_id=p.major_id
  LEFT JOIN sys.certificates AS cert ON p.class=25 AND cert.certificate_id=p.major_id
  LEFT JOIN sys.asymmetric_keys AS ak ON p.class=26 AND ak.asymmetric_key_id=p.major_id
  LEFT JOIN sys.fulltext_stoplists AS fsl ON p.class=29 AND fsl.stoplist_id=p.major_id
  LEFT JOIN sys.registered_search_property_lists AS spl ON p.class=31 AND spl.property_list_id=p.major_id
  LEFT JOIN sys.database_scoped_credentials AS dsc ON p.class=32 AND dsc.credential_id=p.major_id
  LEFT JOIN sys.external_languages AS el ON p.class=34 AND el.external_language_id=p.major_id
  WHERE grantee.name<>N''dbo'' AND NOT (p.class=1 AND p.major_id<0)
 )
 SELECT *,CASE class
    WHEN 0 THEN N''''
    WHEN 1 THEN N'' ON OBJECT::''+QUOTENAME(object_schema_name)+N''.''+QUOTENAME(object_name)
                    +CASE WHEN minor_id=0 THEN N'''' ELSE N'' (''+QUOTENAME(column_name)+N'')'' END
    WHEN 3 THEN N'' ON SCHEMA::''+QUOTENAME(schema_name)
    WHEN 4 THEN N'' ON ''+CASE WHEN target_principal_type=''R'' THEN N''ROLE::'' ELSE N''USER::'' END+QUOTENAME(target_principal_name)
    WHEN 5 THEN N'' ON ASSEMBLY::''+QUOTENAME(assembly_name)
    WHEN 6 THEN N'' ON TYPE::''+QUOTENAME(type_schema_name)+N''.''+QUOTENAME(type_name)
    WHEN 10 THEN N'' ON XML SCHEMA COLLECTION::''+QUOTENAME(xml_schema_name)+N''.''+QUOTENAME(xml_name)
    WHEN 15 THEN N'' ON MESSAGE TYPE::''+QUOTENAME(message_type_name)
    WHEN 16 THEN N'' ON CONTRACT::''+QUOTENAME(contract_name)
    WHEN 17 THEN N'' ON SERVICE::''+QUOTENAME(service_name)
    WHEN 18 THEN N'' ON REMOTE SERVICE BINDING::''+QUOTENAME(remote_binding_name)
    WHEN 19 THEN N'' ON ROUTE::''+QUOTENAME(route_name)
    WHEN 23 THEN N'' ON FULLTEXT CATALOG::''+QUOTENAME(fulltext_catalog_name)
    WHEN 24 THEN N'' ON SYMMETRIC KEY::''+QUOTENAME(symmetric_key_name)
    WHEN 25 THEN N'' ON CERTIFICATE::''+QUOTENAME(certificate_name)
    WHEN 26 THEN N'' ON ASYMMETRIC KEY::''+QUOTENAME(asymmetric_key_name)
    WHEN 29 THEN N'' ON FULLTEXT STOPLIST::''+QUOTENAME(stoplist_name)
    WHEN 31 THEN N'' ON SEARCH PROPERTY LIST::''+QUOTENAME(property_list_name)
    WHEN 32 THEN N'' ON DATABASE SCOPED CREDENTIAL::''+QUOTENAME(credential_name)
    WHEN 34 THEN N'' ON EXTERNAL LANGUAGE::''+QUOTENAME(external_language_name)
   END AS securable_clause
 INTO #RestoredPermissions
 FROM PermissionSource;

 IF EXISTS
 (
   SELECT 1 FROM #RestoredPermissions
   WHERE securable_clause IS NULL OR grantee_name IS NULL
 )
   THROW 51109, ''A restored PROD permission securable or grantee could not be resolved; database remains isolated.'', 1;

 INSERT #Work(command_text)
 SELECT TOP (2147483647) N''REVOKE ''+permission_name+securable_clause+N'' FROM ''+QUOTENAME(grantee_name)+N'' CASCADE;''
 FROM #RestoredPermissions
 ORDER BY CASE WHEN minor_id>0 THEN 0 ELSE 1 END,class,major_id,minor_id DESC;
 DROP TABLE #RestoredPermissions;

 DECLARE @Command nvarchar(max);
 DECLARE permission_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT command_text FROM #Work ORDER BY work_order;
 OPEN permission_cursor; FETCH NEXT FROM permission_cursor INTO @Command;
 WHILE @@FETCH_STATUS=0
 BEGIN EXEC sys.sp_executesql @Command; FETCH NEXT FROM permission_cursor INTO @Command; END;
 CLOSE permission_cursor; DEALLOCATE permission_cursor;
 TRUNCATE TABLE #Work;

 /* Remove every restored role membership before dropping custom roles/users. */
 INSERT #Work(command_text)
 SELECT N''ALTER ROLE ''+QUOTENAME(rolep.name)+N'' DROP MEMBER ''+QUOTENAME(memberp.name)+N'';''
 FROM sys.database_role_members AS rm
 JOIN sys.database_principals AS rolep ON rolep.principal_id=rm.role_principal_id
 JOIN sys.database_principals AS memberp ON memberp.principal_id=rm.member_principal_id
 WHERE memberp.name<>N''dbo'';
 DECLARE membership_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT command_text FROM #Work ORDER BY work_order;
 OPEN membership_cursor; FETCH NEXT FROM membership_cursor INTO @Command;
 WHILE @@FETCH_STATUS=0
 BEGIN EXEC sys.sp_executesql @Command; FETCH NEXT FROM membership_cursor INTO @Command; END;
 CLOSE membership_cursor; DEALLOCATE membership_cursor;
 TRUNCATE TABLE #Work;

 /* Release common ownership dependencies. Any unhandled ownership blocks DROP and rolls back. */
 INSERT #Work(command_text)
 SELECT N''ALTER AUTHORIZATION ON SCHEMA::''+QUOTENAME(name)+N'' TO [dbo];'' FROM sys.schemas WHERE schema_id>4 AND principal_id<>1
 UNION ALL
 SELECT N''ALTER AUTHORIZATION ON ROLE::''+QUOTENAME(name)+N'' TO [dbo];'' FROM sys.database_principals WHERE type=''R'' AND is_fixed_role=0 AND owning_principal_id<>1
 UNION ALL
 SELECT N''ALTER AUTHORIZATION ON OBJECT::''+QUOTENAME(s.name)+N''.''+QUOTENAME(o.name)+N'' TO SCHEMA OWNER;''
 FROM sys.objects AS o JOIN sys.schemas AS s ON s.schema_id=o.schema_id
 WHERE o.is_ms_shipped=0 AND o.principal_id IS NOT NULL;
 DECLARE owner_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT command_text FROM #Work ORDER BY work_order;
 OPEN owner_cursor; FETCH NEXT FROM owner_cursor INTO @Command;
 WHILE @@FETCH_STATUS=0
 BEGIN EXEC sys.sp_executesql @Command; FETCH NEXT FROM owner_cursor INTO @Command; END;
 CLOSE owner_cursor; DEALLOCATE owner_cursor;
 TRUNCATE TABLE #Work;

 INSERT #Work(command_text)
 SELECT N''DROP ROLE ''+QUOTENAME(name)+N'';''
 FROM sys.database_principals WHERE principal_id>4 AND type=''R'' AND is_fixed_role=0
 UNION ALL
 SELECT N''DROP USER ''+QUOTENAME(name)+N'';''
 FROM sys.database_principals WHERE principal_id>4 AND type<>''R'' AND is_fixed_role=0;
 DECLARE drop_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT command_text FROM #Work ORDER BY work_order;
 OPEN drop_cursor; FETCH NEXT FROM drop_cursor INTO @Command;
 WHILE @@FETCH_STATUS=0
 BEGIN EXEC sys.sp_executesql @Command; FETCH NEXT FROM drop_cursor INTO @Command; END;
 CLOSE drop_cursor; DEALLOCATE drop_cursor;

 /* Replay only the saved DEV security commands. */
 DECLARE snapshot_cursor CURSOR LOCAL FAST_FORWARD FOR
   SELECT command_text FROM DBA_Admin.dbo.DevSecuritySnapshotCommand
   WHERE snapshot_id=@SnapshotId ORDER BY command_order;
 OPEN snapshot_cursor; FETCH NEXT FROM snapshot_cursor INTO @Command;
 WHILE @@FETCH_STATUS=0
 BEGIN EXEC sys.sp_executesql @Command; FETCH NEXT FROM snapshot_cursor INTO @Command; END;
 CLOSE snapshot_cursor; DEALLOCATE snapshot_cursor;

 IF EXISTS
 (
   SELECT name,type,authentication_type
   FROM sys.database_principals WHERE principal_id>4 AND is_fixed_role=0
   EXCEPT
   SELECT principal_name COLLATE DATABASE_DEFAULT,principal_type COLLATE DATABASE_DEFAULT,authentication_type
   FROM DBA_Admin.dbo.DevSecuritySnapshotPrincipal WHERE snapshot_id=@SnapshotId
 ) OR EXISTS
 (
   SELECT principal_name COLLATE DATABASE_DEFAULT,principal_type COLLATE DATABASE_DEFAULT,authentication_type
   FROM DBA_Admin.dbo.DevSecuritySnapshotPrincipal WHERE snapshot_id=@SnapshotId
   EXCEPT
   SELECT name,type,authentication_type
   FROM sys.database_principals WHERE principal_id>4 AND is_fixed_role=0
 )
   THROW 51110, ''Principal validation failed; the database was not opened.'', 1;

 IF (SELECT COUNT(*) FROM sys.database_principals WHERE principal_id>4 AND is_fixed_role=0)<>@ExpectedPrincipals
   THROW 51111, ''Principal count validation failed; the database was not opened.'', 1;
 IF (SELECT COUNT(*)
     FROM sys.database_role_members AS rm
     JOIN sys.database_principals AS memberp ON memberp.principal_id=rm.member_principal_id
     WHERE memberp.name<>N''dbo'')<>@ExpectedMemberships
   THROW 51112, ''Role membership validation failed; the database was not opened.'', 1;
 IF (SELECT COUNT(*)
     FROM sys.database_permissions AS p
     JOIN sys.database_principals AS grantee ON grantee.principal_id=p.grantee_principal_id
     WHERE grantee.name<>N''dbo'' AND NOT (p.class=1 AND p.major_id<0))<>@ExpectedPermissions
   THROW 51113, ''Explicit permission validation failed; the database was not opened.'', 1;

 COMMIT;
END TRY
BEGIN CATCH
 IF @@TRANCOUNT>0 ROLLBACK;
 THROW;
END CATCH;';

    BEGIN TRY
      EXEC sys.sp_executesql @Sql,
        N'@SnapshotId uniqueidentifier,@ExpectedPrincipals int,@ExpectedMemberships int,@ExpectedPermissions int',
        @SnapshotId=@SnapshotId,@ExpectedPrincipals=@ExpectedPrincipals,
        @ExpectedMemberships=@ExpectedMemberships,@ExpectedPermissions=@ExpectedPermissions;

      DECLARE @OwnerSql nvarchar(max)=N'ALTER AUTHORIZATION ON DATABASE::'+QUOTENAME(@DatabaseName)+N' TO '+QUOTENAME(@Owner)+N';'
        +N'ALTER DATABASE '+QUOTENAME(@DatabaseName)+N' SET MULTI_USER;';
      EXEC master.sys.sp_executesql @OwnerSql;

      UPDATE dbo.DevSecuritySnapshot
      SET status=N'APPLIED',applied_database=@DatabaseName,applied_at_utc=SYSUTCDATETIME(),error_message=NULL
      WHERE snapshot_id=@SnapshotId;
    END TRY
    BEGIN CATCH
      UPDATE dbo.DevSecuritySnapshot
      SET status=N'FAILED',applied_database=@DatabaseName,error_message=LEFT(ERROR_MESSAGE(),2048)
      WHERE snapshot_id=@SnapshotId;
      /* Deliberately leave the target SINGLE_USER so imported PROD access cannot be used. */
      THROW;
    END CATCH;

    SELECT * FROM dbo.DevSecuritySnapshot WHERE snapshot_id=@SnapshotId;
END;
GO
