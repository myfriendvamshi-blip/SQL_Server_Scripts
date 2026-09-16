/* Run in Session 2 while 01_Blocker_Session.sql is waiting. */
USE DBA_Toolkit_Lab;
SET NOCOUNT ON;
SET LOCK_TIMEOUT 20000;
UPDATE dbo.Account SET Balance=Balance-1 WHERE AccountId=1;
