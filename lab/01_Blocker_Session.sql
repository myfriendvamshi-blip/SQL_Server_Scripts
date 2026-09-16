/* Run in Session 1. It holds a lock for 15 seconds and then rolls back. */
USE DBA_Toolkit_Lab;
SET NOCOUNT ON;
BEGIN TRANSACTION;
UPDATE dbo.Account SET Balance=Balance+1 WHERE AccountId=1;
WAITFOR DELAY '00:00:15';
ROLLBACK TRANSACTION;
