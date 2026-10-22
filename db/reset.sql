-- Reset local test state without dropping the database.
-- Removes auth tokens and accounts created through @example.com test runs,
-- then db/seed.sql re-creates the dummy users/products/tickets.
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;

-- Tokens reference users, so clear them first.
DELETE FROM dbo.Tokens;

DELETE FROM dbo.Tickets
WHERE [Owner_Id] IN (SELECT Id FROM dbo.Users WHERE Email LIKE '%@example.com');

DELETE FROM dbo.Purchases
WHERE [PurchasedBy_Id] IN (SELECT Id FROM dbo.Users WHERE Email LIKE '%@example.com');

DELETE FROM dbo.[Statistics]
WHERE [User_Id] IN (SELECT Id FROM dbo.Users WHERE Email LIKE '%@example.com');

DELETE FROM dbo.Vouchers
WHERE [User_Id] IN (SELECT Id FROM dbo.Users WHERE Email LIKE '%@example.com');

DELETE FROM dbo.Users WHERE Email LIKE '%@example.com';
