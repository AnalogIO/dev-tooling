-- Seed the database with dummy data for the local E2E environment.
-- Run from the analog-dev workspace root with: make seed
-- Vendored from analog-core branch add-sql-scripts
-- (utils/db_scripts/dummy-seed.sql); it is idempotent.

-- creates verified users john@doe.com and many.tickets@analog.local (password 1234).

SET QUOTED_IDENTIFIER ON;
GO

SET NOCOUNT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @SchemaName NVARCHAR(128) = N'dbo';

    DECLARE @DummyUserEmail1 NVARCHAR(256) = N'john@doe.com';
    DECLARE @DummyUserEmail2 NVARCHAR(256) = N'dummy.seed.barista@analog.local';
    DECLARE @DummyUserEmail3 NVARCHAR(256) = N'many.tickets@analog.local';
    DECLARE @LegacyDummyUserEmail1 NVARCHAR(256) = N'dummy.seed.customer@analog.local';
    DECLARE @DummyUserPasswordHash NVARCHAR(256) = N'quXyHEeVCRjSW8GyPFObECr1/oiCrltPRCOUWYqiRx8=';

    DECLARE @ProgrammeShortName NVARCHAR(32) = N'DUMMY';
    DECLARE @ProgrammeFullName NVARCHAR(256) = N'Dummy Programme';
    DECLARE @DefaultProgrammeShortName NVARCHAR(32) = N'SWU';
    DECLARE @DefaultProgrammeFullName NVARCHAR(256) = N'Softwareudvikling';

    DECLARE @ProductName1 NVARCHAR(256) = N'Dummy Seed - 10 Coffee Clips';
    DECLARE @ProductName2 NVARCHAR(256) = N'Dummy Seed - 5 Tea Clips';

    DECLARE @MenuItemName1 NVARCHAR(256) = N'Dummy Seed - Cappuccino';
    DECLARE @MenuItemName2 NVARCHAR(256) = N'Dummy Seed - Latte';
    DECLARE @MenuItemName3 NVARCHAR(256) = N'Dummy Seed - Tea';
    DECLARE @MenuItemName4 NVARCHAR(256) = N'Dummy Seed - Espresso';
    DECLARE @MenuItemName5 NVARCHAR(256) = N'Dummy Seed - Hot Chocolate';
    DECLARE @MenuItemName6 NVARCHAR(256) = N'Dummy Seed - Chai Latte';

    DECLARE @Now DATETIME2 = SYSUTCDATETIME();
    DECLARE @MonthStart DATETIME2 = DATEFROMPARTS(YEAR(@Now), MONTH(@Now), 1);
    DECLARE @MonthEnd DATETIME2 = DATEADD(second, -1, DATEADD(month, 1, @MonthStart));
    DECLARE @SemesterStart DATETIME2;
    DECLARE @SemesterEnd DATETIME2;

    IF MONTH(@Now) >= 7
    BEGIN
        SET @SemesterStart = DATEFROMPARTS(YEAR(@Now), 7, 1);
        SET @SemesterEnd = DATEFROMPARTS(YEAR(@Now), 12, 23);
    END
    ELSE
    BEGIN
        DECLARE @LastDayOfJan DATE = DATEFROMPARTS(YEAR(@Now), 1, 31);
        DECLARE @MondayOffset INT =
            (DATEDIFF(day, CONVERT(date, '19000101', 112), @LastDayOfJan) % 7 + 7) % 7;
        SET @SemesterStart = DATEADD(day, -@MondayOffset, @LastDayOfJan);
        SET @SemesterEnd = DATEFROMPARTS(YEAR(@Now), 6, 30);
    END;

    DECLARE @ProgrammeId INT;
    DECLARE @UserId1 INT;
    DECLARE @UserId2 INT;
    DECLARE @UserId3 INT;
    DECLARE @ProductId1 INT;
    DECLARE @ProductId2 INT;
    DECLARE @MenuItemId1 INT;
    DECLARE @MenuItemId2 INT;
    DECLARE @MenuItemId3 INT;
    DECLARE @MenuItemId4 INT;
    DECLARE @MenuItemId5 INT;
    DECLARE @MenuItemId6 INT;
    DECLARE @PurchaseId1 INT;
    DECLARE @PurchaseId2 INT;
    DECLARE @PurchaseId3 INT;
    DECLARE @PurchaseId4 INT;
    DECLARE @TotalSwipes INT;
    DECLARE @SemesterSwipes INT;
    DECLARE @MonthSwipes INT;
    DECLARE @LastSwipe DATETIME2;

    -- The register endpoint uses programme ID 1 as its backwards-compatible default.
    IF NOT EXISTS (SELECT 1 FROM dbo.Programmes WHERE Id = 1)
    BEGIN
        SET IDENTITY_INSERT dbo.Programmes ON;

        INSERT INTO dbo.Programmes (Id, ShortName, FullName, SortPriority)
        VALUES (1, @DefaultProgrammeShortName, @DefaultProgrammeFullName, 0);

        SET IDENTITY_INSERT dbo.Programmes OFF;
    END;

    -- Ensure a dedicated programme for dummy users exists.
    IF NOT EXISTS (SELECT 1 FROM dbo.Programmes WHERE ShortName = @ProgrammeShortName)
    BEGIN
        INSERT INTO dbo.Programmes (ShortName, FullName, SortPriority)
        VALUES (@ProgrammeShortName, @ProgrammeFullName, 999);
    END;

    SELECT @ProgrammeId = Id
    FROM dbo.Programmes
    WHERE ShortName = @ProgrammeShortName;

    -- Clean up previous dummy rows so this script is rerunnable.
    -- Delete rows that reference the dummy users before deleting the users
    -- themselves (Tokens is the common one: logging in as john@doe.com creates
    -- a token row that would otherwise block the re-seed).
    DELETE tk
    FROM dbo.Tokens tk
    INNER JOIN dbo.Users u ON u.Id = tk.[User_Id]
    WHERE u.Email IN (
        @DummyUserEmail1,
        @DummyUserEmail2,
        @DummyUserEmail3,
        @LegacyDummyUserEmail1
    );

    DELETE s
    FROM dbo.[Statistics] s
    INNER JOIN dbo.Users u ON u.Id = s.[User_Id]
    WHERE u.Email IN (
        @DummyUserEmail1,
        @DummyUserEmail2,
        @DummyUserEmail3,
        @LegacyDummyUserEmail1
    );

    DELETE v
    FROM dbo.Vouchers v
    INNER JOIN dbo.Users u ON u.Id = v.[User_Id]
    WHERE u.Email IN (
        @DummyUserEmail1,
        @DummyUserEmail2,
        @DummyUserEmail3,
        @LegacyDummyUserEmail1
    );

    -- Magic-link tokens that have not been attached to a user yet.
    DELETE FROM dbo.Tokens
    WHERE Email IN (
        @DummyUserEmail1,
        @DummyUserEmail2,
        @DummyUserEmail3,
        @LegacyDummyUserEmail1
    );

    -- Point-of-sale purchases have their own child row, so remove those first.
    DELETE pp
    FROM dbo.PosPurchases pp
    INNER JOIN dbo.Purchases p ON p.Id = pp.PurchaseId
    INNER JOIN dbo.Users u ON u.Id = p.[PurchasedBy_Id]
    WHERE u.Email IN (
        @DummyUserEmail1,
        @DummyUserEmail2,
        @DummyUserEmail3,
        @LegacyDummyUserEmail1
    );

    DELETE t
    FROM dbo.Tickets t
    INNER JOIN dbo.Users u ON u.Id = t.[Owner_Id]
    WHERE u.Email IN (
        @DummyUserEmail1,
        @DummyUserEmail2,
        @DummyUserEmail3,
        @LegacyDummyUserEmail1
    );

    DELETE p
    FROM dbo.Purchases p
    INNER JOIN dbo.Users u ON u.Id = p.[PurchasedBy_Id]
    WHERE u.Email IN (
        @DummyUserEmail1,
        @DummyUserEmail2,
        @DummyUserEmail3,
        @LegacyDummyUserEmail1
    );

    DELETE pug
    FROM dbo.ProductUserGroups pug
    INNER JOIN dbo.Products p ON p.Id = pug.ProductId
    WHERE p.Name IN (@ProductName1, @ProductName2);

    DELETE mip
    FROM dbo.MenuItemProducts mip
    INNER JOIN dbo.Products p ON p.Id = mip.ProductId
    WHERE p.Name IN (@ProductName1, @ProductName2);

    DELETE mip
    FROM dbo.MenuItemProducts mip
    INNER JOIN dbo.MenuItems mi ON mi.Id = mip.MenuItemId
    WHERE mi.Name IN (
        @MenuItemName1,
        @MenuItemName2,
        @MenuItemName3,
        @MenuItemName4,
        @MenuItemName5,
        @MenuItemName6
    );

    DELETE FROM dbo.Products WHERE Name IN (@ProductName1, @ProductName2);
    DELETE FROM dbo.MenuItems
    WHERE Name IN (
        @MenuItemName1,
        @MenuItemName2,
        @MenuItemName3,
        @MenuItemName4,
        @MenuItemName5,
        @MenuItemName6
    );
    DELETE FROM dbo.Users
    WHERE Email IN (
        @DummyUserEmail1,
        @DummyUserEmail2,
        @DummyUserEmail3,
        @LegacyDummyUserEmail1
    );

    -- Insert dummy users.
    -- UserGroup values are ints: Customer=0, Barista=1, Manager=2, Board=3.
    INSERT INTO dbo.Users
        (Email, Name, Password, Salt, Experience, DateCreated, DateUpdated, IsVerified, PrivacyActivated, UserGroup, UserState, [Programme_Id])
    VALUES
        (@DummyUserEmail1, N'John Doe', @DummyUserPasswordHash, N'local-seed', 125, @Now, @Now, 1, 0, 0, N'Active', @ProgrammeId),
        (@DummyUserEmail2, N'Dummy Barista', N'not-a-real-password', N'local-seed', 430, @Now, @Now, 1, 0, 1, N'Active', @ProgrammeId),
        (@DummyUserEmail3, N'Many Tickets', @DummyUserPasswordHash, N'local-seed', 5000, @Now, @Now, 1, 0, 0, N'Active', @ProgrammeId);

    SELECT @UserId1 = Id FROM dbo.Users WHERE Email = @DummyUserEmail1;
    SELECT @UserId2 = Id FROM dbo.Users WHERE Email = @DummyUserEmail2;
    SELECT @UserId3 = Id FROM dbo.Users WHERE Email = @DummyUserEmail3;

    -- Insert dummy products.
    INSERT INTO dbo.Products
        (Price, NumberOfTickets, Name, Description, ExperienceWorth, Visible)
    VALUES
        (250, 10, @ProductName1, N'Dummy local seed product for grouped owned tickets', 10, 1),
        (150, 5, @ProductName2, N'Dummy local seed product for grouped owned tickets', 5, 1);

    SELECT @ProductId1 = Id FROM dbo.Products WHERE Name = @ProductName1;
    SELECT @ProductId2 = Id FROM dbo.Products WHERE Name = @ProductName2;

    INSERT INTO dbo.ProductUserGroups (ProductId, UserGroup)
    VALUES
        (@ProductId1, 0), -- Customer
        (@ProductId1, 2), -- Manager
        (@ProductId2, 0); -- Customer

    -- Insert dummy menu items. The ticket-history user swipes across all of them.
    INSERT INTO dbo.MenuItems (Name, Active)
    VALUES
        (@MenuItemName1, 1),
        (@MenuItemName2, 1),
        (@MenuItemName3, 1),
        (@MenuItemName4, 1),
        (@MenuItemName5, 1),
        (@MenuItemName6, 1);

    SELECT @MenuItemId1 = Id FROM dbo.MenuItems WHERE Name = @MenuItemName1;
    SELECT @MenuItemId2 = Id FROM dbo.MenuItems WHERE Name = @MenuItemName2;
    SELECT @MenuItemId3 = Id FROM dbo.MenuItems WHERE Name = @MenuItemName3;
    SELECT @MenuItemId4 = Id FROM dbo.MenuItems WHERE Name = @MenuItemName4;
    SELECT @MenuItemId5 = Id FROM dbo.MenuItems WHERE Name = @MenuItemName5;
    SELECT @MenuItemId6 = Id FROM dbo.MenuItems WHERE Name = @MenuItemName6;

    INSERT INTO dbo.MenuItemProducts (MenuItemId, ProductId)
    VALUES
        (@MenuItemId1, @ProductId1),
        (@MenuItemId2, @ProductId1),
        (@MenuItemId3, @ProductId2),
        (@MenuItemId4, @ProductId1),
        (@MenuItemId5, @ProductId1),
        (@MenuItemId6, @ProductId1);

    -- Insert purchases and tickets for the original dummy customer.
    INSERT INTO dbo.Purchases
        (ProductName, ProductId, Price, NumberOfTickets, DateCreated, OrderId, ExternalTransactionId, Status, Type, [PurchasedBy_Id])
    VALUES
        (@ProductName1, @ProductId1, 250, 10, @Now, CONVERT(NVARCHAR(36), NEWID()), NULL, N'Completed', N'MobilePayV2', @UserId1),
        (@ProductName2, @ProductId2, 0, 5, @Now, CONVERT(NVARCHAR(36), NEWID()), NULL, N'Completed', N'Free', @UserId1),
        (@ProductName1, @ProductId1, 250, 10, @Now, CONVERT(NVARCHAR(36), NEWID()), NULL, N'Completed', N'MobilePayV2', @UserId2),
        (@ProductName2, @ProductId2, 0, 5, @Now, CONVERT(NVARCHAR(36), NEWID()), NULL, N'Completed', N'Free', @UserId2);

    SELECT TOP(1) @PurchaseId1 = Id
    FROM dbo.Purchases
    WHERE [PurchasedBy_Id] = @UserId1 AND ProductId = @ProductId1
    ORDER BY Id DESC;

    SELECT TOP(1) @PurchaseId2 = Id
    FROM dbo.Purchases
    WHERE [PurchasedBy_Id] = @UserId1 AND ProductId = @ProductId2
    ORDER BY Id DESC;

    SELECT TOP(1) @PurchaseId3 = Id
    FROM dbo.Purchases
    WHERE [PurchasedBy_Id] = @UserId2 AND ProductId = @ProductId1
    ORDER BY Id DESC;

    SELECT TOP(1) @PurchaseId4 = Id
    FROM dbo.Purchases
    WHERE [PurchasedBy_Id] = @UserId2 AND ProductId = @ProductId2
    ORDER BY Id DESC;

    INSERT INTO dbo.Tickets
        (DateCreated, DateUsed, ProductId, IsUsed, Status, [Owner_Id], [Purchase_Id], UsedOnMenuItemId)
    VALUES
        (@Now, NULL, @ProductId1, 0, 0, @UserId1, @PurchaseId1, NULL),
        (@Now, NULL, @ProductId1, 0, 0, @UserId1, @PurchaseId1, NULL),
        (@Now, NULL, @ProductId1, 0, 0, @UserId1, @PurchaseId1, NULL),
        (@Now, @Now, @ProductId1, 1, 1, @UserId1, @PurchaseId1, @MenuItemId1),
        (@Now, NULL, @ProductId2, 0, 0, @UserId1, @PurchaseId2, NULL),
        (@Now, NULL, @ProductId1, 0, 0, @UserId2, @PurchaseId3, NULL),
        (@Now, @Now, @ProductId1, 1, 1, @UserId2, @PurchaseId3, @MenuItemId2),
        (@Now, NULL, @ProductId2, 0, 0, @UserId2, @PurchaseId4, NULL),
        (@Now, @Now, @ProductId2, 1, 1, @UserId2, @PurchaseId4, @MenuItemId3);

    -- ---------------------------------------------------------------------
    -- many.tickets@analog.local: a large, varied ticket/receipt history.
    --
    -- 200 tickets total:
    --   120 used       - across all six menu items and ~1.5 years
    --    70 unused     - so the tickets screen has a lot to show
    --    10 refunded   - hidden from the ticket list, visible on receipts
    --
    -- 25 purchases covering MobilePayV2, Free, Voucher and PointOfSale, plus
    -- Cancelled/Expired/Refunded receipts. One voucher and two POS receipts
    -- exercise the three receipt types.
    -- ---------------------------------------------------------------------
    CREATE TABLE #SeedPurchases
    (
        PurchaseIndex INT NOT NULL PRIMARY KEY,
        ProductId INT NOT NULL,
        ProductName NVARCHAR(256) NOT NULL,
        Price INT NOT NULL,
        NumberOfTickets INT NOT NULL,
        TicketsToCreate INT NOT NULL,
        PurchaseType NVARCHAR(32) NOT NULL,
        PurchaseStatus NVARCHAR(32) NOT NULL,
        DateCreated DATETIME2 NOT NULL,
        OrderId NVARCHAR(36) NOT NULL,
        Id INT NULL
    );

    INSERT INTO #SeedPurchases
        (PurchaseIndex, ProductId, ProductName, Price, NumberOfTickets, TicketsToCreate, PurchaseType, PurchaseStatus, DateCreated, OrderId)
    VALUES
        -- 120 used tickets: 10 coffee purchases and 4 tea purchases.
        (1,  @ProductId1, @ProductName1, 250, 10, 10, N'MobilePayV2', N'Completed', DATEADD(day, -10,  @Now), CONVERT(NVARCHAR(36), NEWID())),
        (2,  @ProductId2, @ProductName2, 150,  5,  5, N'MobilePayV2', N'Completed', DATEADD(day, -20,  @Now), CONVERT(NVARCHAR(36), NEWID())),
        (3,  @ProductId1, @ProductName1, 250, 10, 10, N'MobilePayV2', N'Completed', DATEADD(day, -30,  @Now), CONVERT(NVARCHAR(36), NEWID())),
        (4,  @ProductId2, @ProductName2,   0,  5,  5, N'Free',        N'Completed', DATEADD(day, -40,  @Now), CONVERT(NVARCHAR(36), NEWID())),
        (5,  @ProductId1, @ProductName1,   0, 10, 10, N'Voucher',     N'Completed', DATEADD(day, -50,  @Now), CONVERT(NVARCHAR(36), NEWID())),
        (6,  @ProductId2, @ProductName2,   0,  5,  5, N'Free',        N'Completed', DATEADD(day, -60,  @Now), CONVERT(NVARCHAR(36), NEWID())),
        (7,  @ProductId1, @ProductName1, 250, 10, 10, N'PointOfSale', N'Completed', DATEADD(day, -70,  @Now), CONVERT(NVARCHAR(36), NEWID())),
        (8,  @ProductId2, @ProductName2, 150,  5,  5, N'MobilePayV2', N'Completed', DATEADD(day, -80,  @Now), CONVERT(NVARCHAR(36), NEWID())),
        (9,  @ProductId1, @ProductName1, 250, 10, 10, N'MobilePayV2', N'Completed', DATEADD(day, -90,  @Now), CONVERT(NVARCHAR(36), NEWID())),
        (10, @ProductId1, @ProductName1, 250, 10, 10, N'MobilePayV2', N'Completed', DATEADD(day, -100, @Now), CONVERT(NVARCHAR(36), NEWID())),
        (11, @ProductId1, @ProductName1, 250, 10, 10, N'MobilePayV2', N'Completed', DATEADD(day, -200, @Now), CONVERT(NVARCHAR(36), NEWID())),
        (12, @ProductId1, @ProductName1, 250, 10, 10, N'MobilePayV2', N'Completed', DATEADD(day, -450, @Now), CONVERT(NVARCHAR(36), NEWID())),
        (13, @ProductId1, @ProductName1, 250, 10, 10, N'MobilePayV2', N'Completed', DATEADD(day, -500, @Now), CONVERT(NVARCHAR(36), NEWID())),
        (14, @ProductId1, @ProductName1, 250, 10, 10, N'MobilePayV2', N'Completed', DATEADD(day, -550, @Now), CONVERT(NVARCHAR(36), NEWID())),
        -- 70 unused tickets: recent purchases so the tickets screen has variety.
        (15, @ProductId1, @ProductName1, 250, 10, 10, N'MobilePayV2', N'Completed', DATEADD(day, -35, @Now), CONVERT(NVARCHAR(36), NEWID())),
        (16, @ProductId1, @ProductName1,   0, 10, 10, N'Free',        N'Completed', DATEADD(day, -25, @Now), CONVERT(NVARCHAR(36), NEWID())),
        (17, @ProductId1, @ProductName1, 250, 10, 10, N'MobilePayV2', N'Completed', DATEADD(day, -18, @Now), CONVERT(NVARCHAR(36), NEWID())),
        (18, @ProductId1, @ProductName1, 250, 10, 10, N'PointOfSale', N'Completed', DATEADD(day, -14, @Now), CONVERT(NVARCHAR(36), NEWID())),
        (19, @ProductId1, @ProductName1, 250, 10, 10, N'MobilePayV2', N'Completed', DATEADD(day, -12, @Now), CONVERT(NVARCHAR(36), NEWID())),
        (20, @ProductId1, @ProductName1, 250, 10, 10, N'MobilePayV2', N'Completed', DATEADD(day, -8,  @Now), CONVERT(NVARCHAR(36), NEWID())),
        (21, @ProductId2, @ProductName2,   0,  5,  5, N'Free',        N'Completed', DATEADD(day, -6,  @Now), CONVERT(NVARCHAR(36), NEWID())),
        (22, @ProductId2, @ProductName2, 150,  5,  5, N'MobilePayV2', N'Completed', DATEADD(day, -4,  @Now), CONVERT(NVARCHAR(36), NEWID())),
        -- Non-issued purchases exercise the remaining receipt statuses.
        (23, @ProductId1, @ProductName1, 250, 10, 10, N'MobilePayV2', N'Refunded',  DATEADD(day, -5, @Now), CONVERT(NVARCHAR(36), NEWID())),
        (24, @ProductId1, @ProductName1, 250, 10,  0, N'MobilePayV2', N'Cancelled', DATEADD(day, -3, @Now), CONVERT(NVARCHAR(36), NEWID())),
        (25, @ProductId2, @ProductName2, 150,  5,  0, N'Free',        N'Expired',   DATEADD(day, -2, @Now), CONVERT(NVARCHAR(36), NEWID()));

    CREATE TABLE #InsertedPurchases
    (
        Id INT NOT NULL,
        OrderId NVARCHAR(36) NOT NULL
    );

    INSERT INTO dbo.Purchases
        (ProductName, ProductId, Price, NumberOfTickets, DateCreated, OrderId, ExternalTransactionId, Status, Type, [PurchasedBy_Id])
    OUTPUT INSERTED.Id, INSERTED.OrderId INTO #InsertedPurchases (Id, OrderId)
    SELECT
        ProductName,
        ProductId,
        Price,
        NumberOfTickets,
        DateCreated,
        OrderId,
        NULL,
        PurchaseStatus,
        PurchaseType,
        @UserId3
    FROM #SeedPurchases
    ORDER BY PurchaseIndex;

    UPDATE sp
    SET sp.Id = ip.Id
    FROM #SeedPurchases sp
    INNER JOIN #InsertedPurchases ip ON ip.OrderId = sp.OrderId;

    INSERT INTO dbo.Vouchers
        (Code, DateCreated, DateUsed, Description, Requester, Product_Id, User_Id, PurchaseId)
    SELECT
        N'MANYTICKETS-VOUCHER-1',
        sp.DateCreated,
        sp.DateCreated,
        N'Seed voucher for the ticket-history user',
        N'analog-dev seed',
        sp.ProductId,
        @UserId3,
        sp.Id
    FROM #SeedPurchases sp
    WHERE sp.PurchaseType = N'Voucher';

    INSERT INTO dbo.PosPurchases (PurchaseId, BaristaInitials)
    SELECT sp.Id, N'OM'
    FROM #SeedPurchases sp
    WHERE sp.PurchaseType = N'PointOfSale';

    -- Completed purchases: the first 120 tickets are used, the rest are unused.
    ;WITH nums AS
    (
        SELECT TOP (20) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects
    ),
    completed_tickets AS
    (
        SELECT
            sp.Id AS PurchaseId,
            sp.ProductId,
            sp.DateCreated AS PurchaseDate,
            n.n,
            ROW_NUMBER() OVER (ORDER BY sp.PurchaseIndex, n.n) AS CompletedTicketNo
        FROM #SeedPurchases sp
        INNER JOIN nums n ON n.n <= sp.TicketsToCreate
        WHERE sp.PurchaseStatus = N'Completed'
    )
    INSERT INTO dbo.Tickets
        (DateCreated, DateUsed, ProductId, IsUsed, Status, [Owner_Id], [Purchase_Id], UsedOnMenuItemId)
    SELECT
        CASE
            WHEN d.IsUsed = 1 THEN DATEADD(minute, -30, d.DateUsed)
            ELSE c.PurchaseDate
        END,
        d.DateUsed,
        c.ProductId,
        d.IsUsed,
        d.IsUsed,
        @UserId3,
        c.PurchaseId,
        d.MenuItemId
    FROM completed_tickets c
    CROSS APPLY
    (
        SELECT
            CASE WHEN c.CompletedTicketNo <= 120 THEN 1 ELSE 0 END AS IsUsed,
            CASE
                WHEN c.CompletedTicketNo > 120 THEN NULL
                WHEN c.CompletedTicketNo <= 6 THEN DATEADD(minute, -(c.CompletedTicketNo * 11), @Now)
                WHEN c.CompletedTicketNo <= 20 THEN DATEADD(day, -(c.CompletedTicketNo - 6), @Now)
                WHEN c.CompletedTicketNo <= 40 THEN DATEADD(day, -(c.CompletedTicketNo - 10), @Now)
                WHEN c.CompletedTicketNo <= 60 THEN DATEADD(day, -(c.CompletedTicketNo - 20), @Now)
                WHEN c.CompletedTicketNo <= 90 THEN DATEADD(day, -(c.CompletedTicketNo - 30), @Now)
                ELSE DATEADD(day, -(c.CompletedTicketNo * 4), @Now)
            END AS DateUsed,
            CASE
                WHEN c.CompletedTicketNo > 120 THEN NULL
                WHEN c.ProductId = @ProductId2 THEN @MenuItemId3
                ELSE
                    CASE ((c.CompletedTicketNo - 1) % 5)
                        WHEN 0 THEN @MenuItemId1
                        WHEN 1 THEN @MenuItemId2
                        WHEN 2 THEN @MenuItemId4
                        WHEN 3 THEN @MenuItemId5
                        ELSE @MenuItemId6
                    END
            END AS MenuItemId
    ) d;

    -- Refunded purchase: its tickets keep DateUsed/UsedOnMenuItemId NULL.
    ;WITH nums AS
    (
        SELECT TOP (20) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects
    ),
    refunded_tickets AS
    (
        SELECT
            sp.Id AS PurchaseId,
            sp.ProductId,
            sp.DateCreated AS PurchaseDate,
            n.n
        FROM #SeedPurchases sp
        INNER JOIN nums n ON n.n <= sp.TicketsToCreate
        WHERE sp.PurchaseStatus = N'Refunded'
    )
    INSERT INTO dbo.Tickets
        (DateCreated, DateUsed, ProductId, IsUsed, Status, [Owner_Id], [Purchase_Id], UsedOnMenuItemId)
    SELECT
        c.PurchaseDate,
        NULL,
        c.ProductId,
        0,
        2,
        @UserId3,
        c.PurchaseId,
        NULL
    FROM refunded_tickets c;

    -- Statistics/leaderboard rows for the ticket-history user. Only tickets
    -- from paid purchases count, matching StatisticService's behaviour.
    SELECT
        @TotalSwipes = ISNULL(SUM(CASE WHEN p.Price > 0 THEN 1 ELSE 0 END), 0),
        @SemesterSwipes = ISNULL(
            SUM(
                CASE
                    WHEN p.Price > 0
                        AND t.DateUsed >= @SemesterStart
                        AND t.DateUsed < @SemesterEnd
                    THEN 1
                    ELSE 0
                END
            ),
            0
        ),
        @MonthSwipes = ISNULL(
            SUM(
                CASE
                    WHEN p.Price > 0
                        AND t.DateUsed >= @MonthStart
                        AND t.DateUsed < DATEADD(month, 1, @MonthStart)
                    THEN 1
                    ELSE 0
                END
            ),
            0
        ),
        @LastSwipe = MAX(t.DateUsed)
    FROM dbo.Tickets t
    INNER JOIN dbo.Purchases p ON p.Id = t.[Purchase_Id]
    WHERE t.[Owner_Id] = @UserId3
        AND t.Status = 1;

    INSERT INTO dbo.[Statistics] (Preset, SwipeCount, LastSwipe, ExpiryDate, User_Id)
    VALUES
        (0, @MonthSwipes,    ISNULL(@LastSwipe, @Now), @MonthEnd,                  @UserId3),
        (1, @SemesterSwipes, ISNULL(@LastSwipe, @Now), @SemesterEnd,               @UserId3),
        (2, @TotalSwipes,    ISNULL(@LastSwipe, @Now), DATEADD(year, 100, @Now),   @UserId3);

    COMMIT TRANSACTION;

    SELECT
        @UserId1 AS DummyCustomerUserId,
        @UserId2 AS DummyBaristaUserId,
        @UserId3 AS DummyManyTicketsUserId,
        @ProductId1 AS DummyProductCoffeeId,
        @ProductId2 AS DummyProductTeaId,
        @PurchaseId1 AS DummyPurchaseCoffeeId,
        @PurchaseId2 AS DummyPurchaseTeaId,
        @PurchaseId3 AS DummyBaristaPurchaseCoffeeId,
        @PurchaseId4 AS DummyBaristaPurchaseTeaId,
        (SELECT COUNT(*) FROM dbo.Tickets WHERE [Owner_Id] = @UserId3) AS ManyTicketsTicketCount,
        @MonthSwipes AS ManyTicketsMonthSwipes,
        @SemesterSwipes AS ManyTicketsSemesterSwipes,
        @TotalSwipes AS ManyTicketsTotalSwipes;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;
END CATCH;
