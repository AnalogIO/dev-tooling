-- Seed the local E2E environment with a realistic cafe history.
-- Run from the analog-dev workspace root with: make seed
--
-- Idempotent. Seeded accounts are a@analog.local .. z@analog.local (password 1234
-- for the v1 API login; the app uses the magic-link flow). Every timestamp is
-- relative to SYSUTCDATETIME() at the moment the script runs, so re-seeding
-- always produces fresh, recent-looking activity.

SET QUOTED_IDENTIFIER ON;
GO

SET NOCOUNT ON;

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @SchemaName NVARCHAR(128) = N'dbo';
    DECLARE @Now DATETIME2 = SYSUTCDATETIME();
    DECLARE @PasswordHash NVARCHAR(256) = N'quXyHEeVCRjSW8GyPFObECr1/oiCrltPRCOUWYqiRx8=';
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

    -------------------------------------------------------------------------
    -- Seeded accounts.
    --
    -- a-z@analog.local are all named after people from the AnalogIO GitHub
    -- repositories; the ten biggest coffee drinkers are drawn from the ten
    -- biggest contributors. SwipeTarget is the number of used tickets from
    -- paid purchases, i.e. the leaderboard score.
    -------------------------------------------------------------------------
    DECLARE @SeedUsers TABLE
    (
        UserIndex INT PRIMARY KEY,
        Email NVARCHAR(256) NOT NULL,
        Name NVARCHAR(100) NOT NULL,
        Programme NVARCHAR(16) NOT NULL,
        UserGroup INT NOT NULL,
        PrivacyActivated BIT NOT NULL,
        ProfileIcon INT NOT NULL,
        ProfileBackgroundColor INT NOT NULL,
        Experience INT NOT NULL,
        JoinedDaysAgo INT NOT NULL,
        IsVerified BIT NOT NULL,
        UserState NVARCHAR(32) NOT NULL,
        SwipeTarget INT NOT NULL,
        PurchaseCount INT NOT NULL,
        RangeDays INT NOT NULL
    );

    INSERT INTO @SeedUsers
        (UserIndex, Email, Name, Programme, UserGroup, PrivacyActivated, ProfileIcon, ProfileBackgroundColor, Experience, JoinedDaysAgo, IsVerified, UserState, SwipeTarget, PurchaseCount, RangeDays)
    VALUES
        ( 1, N'a@analog.local', N'Omid',       N'SWU',  0, 0, 0, 0, 1500, 600, 1, N'Active', 120, 25, 540),
        ( 2, N'b@analog.local', N'Jonas',      N'SWU',  0, 0, 1, 1,  900, 480, 1, N'Active',  78, 12, 420),
        ( 3, N'c@analog.local', N'Frederik J.',N'DATA', 0, 0, 2, 2,  850, 480, 1, N'Active',  72, 12, 420),
        ( 4, N'd@analog.local', N'Frederik M.',N'GBI',  0, 0, 3, 3,  800, 450, 1, N'Active',  66, 10, 400),
        ( 5, N'e@analog.local', N'Thomas',     N'DDIT', 0, 0, 4, 4,  750, 450, 1, N'Active',  60, 10, 400),
        ( 6, N'f@analog.local', N'Mikael',     N'DIM',  0, 0, 5, 5,  600, 420, 1, N'Active',  44,  8, 380),
        ( 7, N'g@analog.local', N'Frederik D.',N'GAMES',0, 0, 6, 6,  550, 400, 1, N'Active',  41,  8, 360),
        ( 8, N'h@analog.local', N'Fischer',    N'SD',   0, 0, 7, 7,  500, 400, 1, N'Active',  38,  7, 360),
        ( 9, N'i@analog.local', N'Andreas',    N'CS',   0, 0, 8, 8,  450, 380, 1, N'Active',  34,  7, 340),
        (10, N'j@analog.local', N'Anders',     N'EXCH', 0, 0, 9, 9,  420, 360, 1, N'Active',  31,  6, 320),
        (11, N'k@analog.local', N'Colin',      N'SWU',  0, 0, 0, 1,  350, 300, 1, N'Active',  28,  5, 240),
        (12, N'l@analog.local', N'Kasper',     N'DATA', 0, 0, 1, 2,  320, 280, 1, N'Active',  24,  5, 220),
        (13, N'm@analog.local', N'Lauritz',    N'SWU',  1, 0, 2, 3,  260, 260, 1, N'Active',  14,  4, 200),
        (14, N'n@analog.local', N'Andreas G.', N'DATA', 1, 0, 3, 4,  220, 240, 1, N'Active',  11,  3, 180),
        (15, N'o@analog.local', N'Monir',      N'GBI',  1, 0, 4, 5,  200, 220, 1, N'Active',   8,  3, 150),
        (16, N'p@analog.local', N'Frederik P.',N'DIM',  2, 0, 5, 6,  300, 260, 1, N'Active',  18,  5, 240),
        (17, N'q@analog.local', N'Jacob',      N'CS',   3, 0, 6, 7,  380, 300, 1, N'Active',  25,  6, 260),
        (18, N'r@analog.local', N'buschbirk',  N'DDIT', 0, 0, 7, 8,  260, 220, 1, N'Active',  18,  4, 200),
        (19, N's@analog.local', N'Simon',      N'EXCH', 0, 0, 8, 9,  240, 200, 1, N'Active',  16,  4, 180),
        (20, N't@analog.local', N'jstcz',      N'SWU',  0, 0, 9, 0,  200, 180, 1, N'Active',  12,  3, 160),
        (21, N'u@analog.local', N'Christoffer',N'DATA', 0, 0, 0, 1,  180, 160, 1, N'Active',  10,  3, 140),
        (22, N'v@analog.local', N'Mathias',    N'DDIT', 0, 0, 1, 2,  150, 140, 1, N'Active',   8,  3, 120),
        (23, N'w@analog.local', N'Daniel',     N'GBI',  0, 1, 2, 3,  120, 120, 1, N'Active',   6,  2, 100),
        (24, N'x@analog.local', N'Chrisser000',N'SWU',  0, 0, 3, 4,    0,   3, 1, N'Active',   0,  0,   0),
        (25, N'y@analog.local', N'Sam',        N'DATA', 0, 0, 4, 5,    0,   6, 0, N'PendingActivition', 0, 0, 0),
        (26, N'z@analog.local', N'Hubert',     N'CS',   0, 0, 5, 6,   80, 100, 1, N'Active',   4,  2,  90);

    -- Accounts from older versions of this seed (and one renamed fixture on
    -- this developer machine) are removed so re-seeding never duplicates them.
    DECLARE @LegacyEmails TABLE (Email NVARCHAR(256) PRIMARY KEY);
    INSERT INTO @LegacyEmails (Email) VALUES
        (N'john@doe.com'),
        (N'many.tickets@analog.local'),
        (N'dummy.seed.barista@analog.local'),
        (N'dummy.seed.customer@analog.local'),
        (N'tix@analog.dk');

    CREATE TABLE #SeedEmails (Email NVARCHAR(256) PRIMARY KEY);
    INSERT INTO #SeedEmails (Email) SELECT Email FROM @SeedUsers;
    INSERT INTO #SeedEmails (Email)
    SELECT Email FROM @LegacyEmails l
    WHERE NOT EXISTS (SELECT 1 FROM #SeedEmails s WHERE s.Email = l.Email);

    -- Accounts from the previous version of this seed used @analog.dk.
    INSERT INTO #SeedEmails (Email)
    SELECT u.Email
    FROM dbo.Users u
    WHERE u.Email LIKE N'[a-z]@analog.dk'
      AND NOT EXISTS (SELECT 1 FROM #SeedEmails s WHERE s.Email = u.Email);

    -- Delete rows referencing the seeded users before the users themselves.
    DELETE tk
    FROM dbo.Tokens tk
    INNER JOIN dbo.Users u ON u.Id = tk.[User_Id]
    WHERE u.Email IN (SELECT Email FROM #SeedEmails);

    DELETE FROM dbo.Tokens WHERE Email IN (SELECT Email FROM #SeedEmails);

    DELETE st
    FROM dbo.[Statistics] st
    INNER JOIN dbo.Users u ON u.Id = st.[User_Id]
    WHERE u.Email IN (SELECT Email FROM #SeedEmails);

    DELETE v
    FROM dbo.Vouchers v
    INNER JOIN dbo.Users u ON u.Id = v.[User_Id]
    WHERE u.Email IN (SELECT Email FROM #SeedEmails);

    DELETE pp
    FROM dbo.PosPurchases pp
    INNER JOIN dbo.Purchases p ON p.Id = pp.PurchaseId
    INNER JOIN dbo.Users u ON u.Id = p.[PurchasedBy_Id]
    WHERE u.Email IN (SELECT Email FROM #SeedEmails);

    DELETE t
    FROM dbo.Tickets t
    INNER JOIN dbo.Users u ON u.Id = t.[Owner_Id]
    WHERE u.Email IN (SELECT Email FROM #SeedEmails);

    DELETE p
    FROM dbo.Purchases p
    INNER JOIN dbo.Users u ON u.Id = p.[PurchasedBy_Id]
    WHERE u.Email IN (SELECT Email FROM #SeedEmails);

    DELETE FROM dbo.Users WHERE Email IN (SELECT Email FROM #SeedEmails);

    -- Voucher codes issued by this seed (including unredeemed ones).
    DELETE FROM dbo.Vouchers
    WHERE Code LIKE N'SEED-%' OR Code = N'MANYTICKETS-VOUCHER-1';

    -------------------------------------------------------------------------
    -- Programmes. ID 1 must stay the default used by the registration flow.
    -------------------------------------------------------------------------
    IF NOT EXISTS (SELECT 1 FROM dbo.Programmes WHERE Id = 1)
    BEGIN
        SET IDENTITY_INSERT dbo.Programmes ON;
        INSERT INTO dbo.Programmes (Id, ShortName, FullName, SortPriority, IsActive)
        VALUES (1, N'SWU', N'Softwareudvikling', 0, 1);
        SET IDENTITY_INSERT dbo.Programmes OFF;
    END
    ELSE
    BEGIN
        UPDATE dbo.Programmes
        SET ShortName = N'SWU', FullName = N'Softwareudvikling', SortPriority = 0, IsActive = 1
        WHERE Id = 1;
    END;

    -- Users who still point at the old DUMMY programme are moved to the
    -- default before it is removed (the FK is ON DELETE CASCADE).
    DECLARE @DummyProgrammeId INT =
        (SELECT Id FROM dbo.Programmes WHERE ShortName = N'DUMMY' AND Id <> 1);
    IF @DummyProgrammeId IS NOT NULL
    BEGIN
        UPDATE dbo.Users SET Programme_Id = 1 WHERE Programme_Id = @DummyProgrammeId;
        DELETE FROM dbo.Programmes WHERE Id = @DummyProgrammeId;
    END;

    DECLARE @Programmes TABLE
    (
        ShortName NVARCHAR(32) PRIMARY KEY,
        FullName NVARCHAR(256) NOT NULL,
        SortPriority INT NOT NULL,
        IsActive BIT NOT NULL
    );

    INSERT INTO @Programmes (ShortName, FullName, SortPriority, IsActive) VALUES
        (N'SWU',  N'Softwareudvikling', 0, 1),
        (N'DATA', N'Datalogi', 10, 1),
        (N'GBI',  N'Global Business Informatics', 20, 1),
        (N'DDIT', N'Digital Design og Interaktive Teknologier', 30, 1),
        (N'DIM',  N'Digital Innovation & Management', 40, 1),
        (N'GAMES',N'Spiludvikling', 50, 1),
        (N'SD',   N'Software Design', 60, 1),
        (N'CS',   N'Computer Science', 70, 1),
        (N'EXCH', N'Exchange Student', 80, 1),
        (N'MMD',  N'Multimedia Design', 999, 0);

    INSERT INTO dbo.Programmes (ShortName, FullName, SortPriority, IsActive)
    SELECT p.ShortName, p.FullName, p.SortPriority, p.IsActive
    FROM @Programmes p
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Programmes x WHERE x.ShortName = p.ShortName);

    UPDATE x
    SET FullName = p.FullName, SortPriority = p.SortPriority, IsActive = p.IsActive
    FROM dbo.Programmes x
    INNER JOIN @Programmes p ON p.ShortName = x.ShortName;

    -------------------------------------------------------------------------
    -- Products. Production-style group names, without "Card" or clip counts.
    -------------------------------------------------------------------------
    DECLARE @Products TABLE
    (
        Name NVARCHAR(256) PRIMARY KEY,
        Description NVARCHAR(MAX) NOT NULL,
        Price INT NOT NULL,
        NumberOfTickets INT NOT NULL,
        ExperienceWorth INT NOT NULL,
        Visible BIT NOT NULL
    );

    INSERT INTO @Products (Name, Description, Price, NumberOfTickets, ExperienceWorth, Visible) VALUES
        (N'Small',        N'10 coffee clips', 250, 10, 10, 1),
        (N'Large',        N'20 coffee clips', 450, 20, 20, 1),
        (N'Fancy',        N'10 clips for fancy drinks', 300, 10, 10, 1),
        (N'Filter',       N'10 filter coffee clips', 180, 10, 10, 1),
        (N'Tea',          N'10 tea clips', 200, 10, 10, 1),
        (N'Iced',         N'5 iced coffee clips', 140, 5, 5, 1),
        (N'Hot Chocolate',N'5 hot chocolate clips', 125, 5, 5, 1),
        (N'Single',       N'1 coffee clip', 35, 1, 1, 1),
        (N'Semester',     N'50 coffee clips', 950, 50, 50, 1),
        (N'Free',         N'1 free coffee clip', 0, 1, 1, 1),
        (N'Barista',      N'10 staff clips', 0, 10, 10, 1),
        (N'Board',        N'10 board clips', 0, 10, 10, 1),
        (N'Christmas',    N'10 coffee clips (archived)', 200, 10, 10, 0);

    -- Rename the old seed products in place so historical purchases keep
    -- their foreign keys instead of being deleted by the cascade.
    IF EXISTS (SELECT 1 FROM dbo.Products WHERE Name = N'Dummy Seed - 10 Coffee Clips')
       AND NOT EXISTS (SELECT 1 FROM dbo.Products WHERE Name = N'Small')
        UPDATE dbo.Products SET Name = N'Small' WHERE Name = N'Dummy Seed - 10 Coffee Clips';

    IF EXISTS (SELECT 1 FROM dbo.Products WHERE Name = N'Dummy Seed - 5 Tea Clips')
       AND NOT EXISTS (SELECT 1 FROM dbo.Products WHERE Name = N'Tea')
        UPDATE dbo.Products SET Name = N'Tea' WHERE Name = N'Dummy Seed - 5 Tea Clips';

    INSERT INTO dbo.Products (Price, NumberOfTickets, Name, Description, ExperienceWorth, Visible)
    SELECT p.Price, p.NumberOfTickets, p.Name, p.Description, p.ExperienceWorth, p.Visible
    FROM @Products p
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Products x WHERE x.Name = p.Name);

    UPDATE x
    SET Price = p.Price,
        NumberOfTickets = p.NumberOfTickets,
        Description = p.Description,
        ExperienceWorth = p.ExperienceWorth,
        Visible = p.Visible
    FROM dbo.Products x
    INNER JOIN @Products p ON p.Name = x.Name;

    -- Anything still carrying an old name is either deleted (unreferenced)
    -- or archived with a neutral name so the data never says "Dummy".
    UPDATE dbo.Products
    SET Name = REPLACE(Name, N'Dummy Seed - ', N'Legacy '), Visible = 0
    WHERE Name LIKE N'Dummy Seed - %';

    DECLARE @ProductLookup TABLE
    (
        Name NVARCHAR(256) PRIMARY KEY,
        Id INT NOT NULL,
        Price INT NOT NULL,
        NumberOfTickets INT NOT NULL
    );

    INSERT INTO @ProductLookup (Name, Id, Price, NumberOfTickets)
    SELECT p.Name, MIN(p.Id), MIN(p.Price), MIN(p.NumberOfTickets)
    FROM dbo.Products p
    INNER JOIN @Products s ON s.Name = p.Name
    GROUP BY p.Name;

    -- Old purchases keep a denormalised copy of the product name.
    UPDATE p
    SET ProductName = l.Name
    FROM dbo.Purchases p
    INNER JOIN @ProductLookup l ON l.Id = p.ProductId
    WHERE p.ProductName LIKE N'Dummy Seed - %';

    -------------------------------------------------------------------------
    -- Menu items (drinks that a clip can be redeemed for).
    -------------------------------------------------------------------------
    DECLARE @MenuItems TABLE
    (
        Name NVARCHAR(256) PRIMARY KEY,
        Active BIT NOT NULL
    );

    INSERT INTO @MenuItems (Name, Active) VALUES
        (N'Espresso', 1),
        (N'Filter Coffee', 1),
        (N'Cappuccino', 1),
        (N'Latte', 1),
        (N'Flat White', 1),
        (N'Cortado', 1),
        (N'Americano', 1),
        (N'Cold Brew', 1),
        (N'Iced Latte', 1),
        (N'Matcha Latte', 1),
        (N'Chai Latte', 1),
        (N'Tea', 1),
        (N'Hot Chocolate', 1),
        (N'Pumpkin Spice Latte', 0);

    IF EXISTS (SELECT 1 FROM dbo.MenuItems WHERE Name = N'Dummy Seed - Cappuccino')
       AND NOT EXISTS (SELECT 1 FROM dbo.MenuItems WHERE Name = N'Cappuccino')
        UPDATE dbo.MenuItems SET Name = N'Cappuccino' WHERE Name = N'Dummy Seed - Cappuccino';

    IF EXISTS (SELECT 1 FROM dbo.MenuItems WHERE Name = N'Dummy Seed - Latte')
       AND NOT EXISTS (SELECT 1 FROM dbo.MenuItems WHERE Name = N'Latte')
        UPDATE dbo.MenuItems SET Name = N'Latte' WHERE Name = N'Dummy Seed - Latte';

    IF EXISTS (SELECT 1 FROM dbo.MenuItems WHERE Name = N'Dummy Seed - Tea')
       AND NOT EXISTS (SELECT 1 FROM dbo.MenuItems WHERE Name = N'Tea')
        UPDATE dbo.MenuItems SET Name = N'Tea' WHERE Name = N'Dummy Seed - Tea';

    IF EXISTS (SELECT 1 FROM dbo.MenuItems WHERE Name = N'Dummy Seed - Espresso')
       AND NOT EXISTS (SELECT 1 FROM dbo.MenuItems WHERE Name = N'Espresso')
        UPDATE dbo.MenuItems SET Name = N'Espresso' WHERE Name = N'Dummy Seed - Espresso';

    IF EXISTS (SELECT 1 FROM dbo.MenuItems WHERE Name = N'Dummy Seed - Hot Chocolate')
       AND NOT EXISTS (SELECT 1 FROM dbo.MenuItems WHERE Name = N'Hot Chocolate')
        UPDATE dbo.MenuItems SET Name = N'Hot Chocolate' WHERE Name = N'Dummy Seed - Hot Chocolate';

    IF EXISTS (SELECT 1 FROM dbo.MenuItems WHERE Name = N'Dummy Seed - Chai Latte')
       AND NOT EXISTS (SELECT 1 FROM dbo.MenuItems WHERE Name = N'Chai Latte')
        UPDATE dbo.MenuItems SET Name = N'Chai Latte' WHERE Name = N'Dummy Seed - Chai Latte';

    UPDATE dbo.MenuItems
    SET Name = REPLACE(Name, N'Dummy Seed - ', N'Legacy '), Active = 0
    WHERE Name LIKE N'Dummy Seed - %';

    INSERT INTO dbo.MenuItems (Name, Active)
    SELECT m.Name, m.Active
    FROM @MenuItems m
    WHERE NOT EXISTS (SELECT 1 FROM dbo.MenuItems x WHERE x.Name = m.Name);

    UPDATE x
    SET Active = m.Active
    FROM dbo.MenuItems x
    INNER JOIN @MenuItems m ON m.Name = x.Name;

    -------------------------------------------------------------------------
    -- Product eligibility: which user groups can buy a product and which
    -- drinks each product can be redeemed for.
    -------------------------------------------------------------------------
    DECLARE @ProductGroups TABLE
    (
        ProductName NVARCHAR(256) NOT NULL,
        UserGroup INT NOT NULL,
        PRIMARY KEY (ProductName, UserGroup)
    );

    INSERT INTO @ProductGroups (ProductName, UserGroup) VALUES
        (N'Small', 0), (N'Large', 0), (N'Fancy', 0), (N'Filter', 0), (N'Tea', 0),
        (N'Iced', 0), (N'Hot Chocolate', 0), (N'Single', 0), (N'Semester', 0),
        (N'Free', 0), (N'Christmas', 0),
        (N'Barista', 1),
        (N'Board', 2), (N'Board', 3);

    DELETE pug
    FROM dbo.ProductUserGroups pug
    INNER JOIN @ProductLookup l ON l.Id = pug.ProductId;

    INSERT INTO dbo.ProductUserGroups (ProductId, UserGroup)
    SELECT l.Id, g.UserGroup
    FROM @ProductGroups g
    INNER JOIN @ProductLookup l ON l.Name = g.ProductName;

    DECLARE @ProductMenuItems TABLE
    (
        ProductName NVARCHAR(256) NOT NULL,
        MenuItemName NVARCHAR(256) NOT NULL,
        PRIMARY KEY (ProductName, MenuItemName)
    );

    -- Coffee cards.
    INSERT INTO @ProductMenuItems (ProductName, MenuItemName)
    SELECT p.Name, m.Name
    FROM (VALUES (N'Small'), (N'Large'), (N'Semester'), (N'Christmas')) p(Name)
    CROSS JOIN (VALUES (N'Espresso'), (N'Filter Coffee'), (N'Cappuccino'), (N'Latte'),
                       (N'Flat White'), (N'Cortado'), (N'Americano')) m(Name);

    -- Fancy drinks card.
    INSERT INTO @ProductMenuItems (ProductName, MenuItemName) VALUES
        (N'Fancy', N'Flat White'), (N'Fancy', N'Cortado'), (N'Fancy', N'Cappuccino'),
        (N'Fancy', N'Latte'), (N'Fancy', N'Matcha Latte'), (N'Fancy', N'Chai Latte'),
        (N'Fancy', N'Hot Chocolate');

    -- Filter card.
    INSERT INTO @ProductMenuItems (ProductName, MenuItemName) VALUES
        (N'Filter', N'Filter Coffee'), (N'Filter', N'Americano'), (N'Filter', N'Espresso');

    -- Tea card.
    INSERT INTO @ProductMenuItems (ProductName, MenuItemName) VALUES
        (N'Tea', N'Tea'), (N'Tea', N'Chai Latte'), (N'Tea', N'Matcha Latte');

    -- Iced card.
    INSERT INTO @ProductMenuItems (ProductName, MenuItemName) VALUES
        (N'Iced', N'Iced Latte'), (N'Iced', N'Cold Brew');

    -- Single item cards.
    INSERT INTO @ProductMenuItems (ProductName, MenuItemName) VALUES
        (N'Hot Chocolate', N'Hot Chocolate'),
        (N'Single', N'Espresso'), (N'Single', N'Filter Coffee'), (N'Single', N'Americano'),
        (N'Free', N'Filter Coffee'), (N'Free', N'Espresso');

    -- Staff cards work for everything on the menu.
    INSERT INTO @ProductMenuItems (ProductName, MenuItemName)
    SELECT p.Name, m.Name
    FROM (VALUES (N'Barista'), (N'Board')) p(Name)
    CROSS JOIN (SELECT Name FROM @MenuItems WHERE Active = 1) m;

    DELETE mip
    FROM dbo.MenuItemProducts mip
    INNER JOIN @ProductLookup l ON l.Id = mip.ProductId;

    INSERT INTO dbo.MenuItemProducts (MenuItemId, ProductId)
    SELECT mi.Id, l.Id
    FROM @ProductMenuItems x
    INNER JOIN @ProductLookup l ON l.Name = x.ProductName
    INNER JOIN dbo.MenuItems mi ON mi.Name = x.MenuItemName;

    -------------------------------------------------------------------------
    -- Users.
    -------------------------------------------------------------------------
    CREATE TABLE #SeedUserIds (Email NVARCHAR(256) PRIMARY KEY, Id INT NOT NULL);

    INSERT INTO dbo.Users
        (Email, Name, Password, Salt, Experience, DateCreated, DateUpdated, IsVerified,
         PrivacyActivated, UserGroup, UserState, [Programme_Id], ProfileIcon, ProfileBackgroundColor)
    OUTPUT INSERTED.Email, INSERTED.Id INTO #SeedUserIds (Email, Id)
    SELECT
        su.Email,
        su.Name,
        @PasswordHash,
        N'local-seed',
        su.Experience,
        DATEADD(day, -su.JoinedDaysAgo, @Now),
        DATEADD(day, -su.JoinedDaysAgo, @Now),
        su.IsVerified,
        su.PrivacyActivated,
        su.UserGroup,
        su.UserState,
        p.Id,
        su.ProfileIcon,
        su.ProfileBackgroundColor
    FROM @SeedUsers su
    INNER JOIN dbo.Programmes p ON p.ShortName = su.Programme;

    -------------------------------------------------------------------------
    -- Purchases: a recency-biased mix per user, dated relative to @Now.
    -------------------------------------------------------------------------
    DECLARE @StatusOverrides TABLE
    (
        Email NVARCHAR(256) NOT NULL,
        PurchaseIndex INT NOT NULL,
        Status NVARCHAR(32) NOT NULL,
        PRIMARY KEY (Email, PurchaseIndex)
    );

    INSERT INTO @StatusOverrides (Email, PurchaseIndex, Status) VALUES
        (N'a@analog.local',  2, N'Refunded'),
        (N'b@analog.local',  3, N'Refunded'),
        (N'c@analog.local',  1, N'Cancelled'),
        (N'd@analog.local',  2, N'Expired'),
        (N'e@analog.local',  4, N'Refunded'),
        (N'f@analog.local',  2, N'Cancelled'),
        (N'k@analog.local',  1, N'Expired'),
        (N'q@analog.local',  3, N'Refunded'),
        (N'r@analog.local',  2, N'Cancelled'),
        (N's@analog.local',  1, N'Expired');

    -- A few explicit non-MobilePay purchases so every receipt type shows up
    -- regardless of the random roll.
    DECLARE @TypeOverrides TABLE
    (
        Email NVARCHAR(256) NOT NULL,
        PurchaseIndex INT NOT NULL,
        PurchaseType NVARCHAR(32) NOT NULL,
        PRIMARY KEY (Email, PurchaseIndex)
    );

    INSERT INTO @TypeOverrides (Email, PurchaseIndex, PurchaseType) VALUES
        (N'a@analog.local', 5, N'Voucher'),
        (N'b@analog.local', 6, N'Voucher'),
        (N'c@analog.local', 4, N'Voucher'),
        (N'd@analog.local', 5, N'Voucher'),
        (N'e@analog.local', 6, N'Voucher'),
        (N'k@analog.local', 3, N'Voucher'),
        (N'a@analog.local', 7, N'PointOfSale'),
        (N'b@analog.local', 5, N'PointOfSale'),
        (N'c@analog.local', 6, N'PointOfSale'),
        (N'e@analog.local', 7, N'PointOfSale'),
        (N'f@analog.local', 4, N'PointOfSale'),
        (N'g@analog.local', 3, N'PointOfSale'),
        (N'h@analog.local', 3, N'PointOfSale'),
        (N'i@analog.local', 3, N'PointOfSale'),
        (N'm@analog.local', 4, N'PointOfSale'),
        (N'p@analog.local', 3, N'PointOfSale'),
        (N'r@analog.local', 3, N'PointOfSale'),
        (N's@analog.local', 2, N'PointOfSale');

    CREATE TABLE #PurchasePlan
    (
        PurchaseKey INT IDENTITY(1, 1) PRIMARY KEY,
        Email NVARCHAR(256) NOT NULL,
        ProductId INT NOT NULL,
        ProductName NVARCHAR(256) NOT NULL,
        Price INT NOT NULL,
        NumberOfTickets INT NOT NULL,
        DateCreated DATETIME2 NOT NULL,
        PurchaseType NVARCHAR(32) NOT NULL,
        PurchaseStatus NVARCHAR(32) NOT NULL,
        DaysSince INT NOT NULL,
        OrderId NVARCHAR(36) NOT NULL,
        ExternalTransactionId NVARCHAR(36) NULL,
        Id INT NULL
    );

    ;WITH nums AS
    (
        SELECT TOP (30) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS i
        FROM sys.all_objects
    )
    INSERT INTO #PurchasePlan
        (Email, ProductId, ProductName, Price, NumberOfTickets, DateCreated,
         PurchaseType, PurchaseStatus, DaysSince, OrderId, ExternalTransactionId)
    SELECT
        u.Email,
        l.Id,
        l.Name,
        CASE
            WHEN l.Price = 0 OR t.PurchaseType IN (N'Free', N'Voucher') THEN 0
            ELSE l.Price
        END,
        l.NumberOfTickets,
        CASE
            -- Never place a purchase in the future; a purchase "today" is
            -- clamped to the last couple of hours before @Now.
            WHEN c.Candidate > DATEADD(minute, -5, @Now)
                THEN DATEADD(minute, -(ABS(CHECKSUM(u.Email, n.i, 3)) % 120), @Now)
            ELSE c.Candidate
        END,
        t.PurchaseType,
        COALESCE(o.Status, N'Completed'),
        d.DaysSince,
        CONVERT(NVARCHAR(36), NEWID()),
        CASE WHEN t.PurchaseType = N'MobilePayV2' THEN CONVERT(NVARCHAR(36), NEWID()) ELSE NULL END
    FROM @SeedUsers u
    INNER JOIN nums n ON n.i <= u.PurchaseCount
    CROSS APPLY
    (
        SELECT CASE
            WHEN u.PurchaseCount <= 1 THEN 2
            ELSE 2 + CAST(((n.i - 1.0) / (u.PurchaseCount - 1)) * (u.RangeDays - 2) AS INT)
        END AS DaysSince
    ) d
    CROSS APPLY
    (
        SELECT CASE
            WHEN u.UserGroup = 1 AND (u.UserIndex + n.i) % 4 = 0 THEN N'Barista'
            WHEN u.UserGroup IN (2, 3) AND (u.UserIndex + n.i) % 5 = 0 THEN N'Board'
            ELSE
                CASE (u.UserIndex + n.i) % 10
                    WHEN 0 THEN N'Small'
                    WHEN 1 THEN N'Large'
                    WHEN 2 THEN N'Fancy'
                    WHEN 3 THEN N'Filter'
                    WHEN 4 THEN N'Tea'
                    WHEN 5 THEN N'Small'
                    WHEN 6 THEN N'Large'
                    WHEN 7 THEN N'Iced'
                    WHEN 8 THEN N'Hot Chocolate'
                    ELSE N'Fancy'
                END
        END AS ProductName
    ) p
    INNER JOIN @ProductLookup l ON l.Name = p.ProductName
    CROSS APPLY
    (
        SELECT ABS(CHECKSUM(NEWID())) % 100 AS Roll
    ) r
    CROSS APPLY
    (
        -- Guarantee enough paid clips to reach the user's leaderboard target;
        -- an occasional free staff card is covered by the extra purchase.
        SELECT CAST(CEILING(u.SwipeTarget / 5.0) AS INT) + 1 AS PaidPurchases
    ) pp
    LEFT JOIN @TypeOverrides ot
        ON ot.Email = u.Email AND ot.PurchaseIndex = n.i
    CROSS APPLY
    (
        SELECT CASE
            WHEN l.Price = 0 THEN N'Free'
            WHEN ot.PurchaseType IS NOT NULL THEN ot.PurchaseType
            WHEN n.i <= pp.PaidPurchases THEN N'MobilePayV2'
            WHEN r.Roll < 10 THEN N'Free'
            WHEN r.Roll < 16 THEN N'Voucher'
            WHEN r.Roll < 26 THEN N'PointOfSale'
            ELSE N'MobilePayV2'
        END AS PurchaseType
    ) t
    CROSS APPLY
    (
        SELECT DATEADD(
                   minute,
                   ABS(CHECKSUM(u.Email, n.i, 11)) % 540,
                   DATEADD(hour, 7, CAST(CAST(DATEADD(day, -d.DaysSince, @Now) AS DATE) AS DATETIME2))
               ) AS Candidate
    ) c
    LEFT JOIN @StatusOverrides o
        ON o.Email = u.Email AND o.PurchaseIndex = n.i
    ORDER BY u.UserIndex, n.i;

    CREATE TABLE #InsertedPurchases (Id INT NOT NULL, OrderId NVARCHAR(36) NOT NULL);

    INSERT INTO dbo.Purchases
        (ProductName, ProductId, Price, NumberOfTickets, DateCreated, OrderId,
         ExternalTransactionId, Status, Type, [PurchasedBy_Id])
    OUTPUT INSERTED.Id, INSERTED.OrderId INTO #InsertedPurchases (Id, OrderId)
    SELECT
        pp.ProductName,
        pp.ProductId,
        pp.Price,
        pp.NumberOfTickets,
        pp.DateCreated,
        pp.OrderId,
        pp.ExternalTransactionId,
        pp.PurchaseStatus,
        pp.PurchaseType,
        u.Id
    FROM #PurchasePlan pp
    INNER JOIN #SeedUserIds u ON u.Email = pp.Email
    ORDER BY pp.PurchaseKey;

    UPDATE pp
    SET pp.Id = ip.Id
    FROM #PurchasePlan pp
    INNER JOIN #InsertedPurchases ip ON ip.OrderId = pp.OrderId;

    -------------------------------------------------------------------------
    -- Tickets: refunded rows first, then one unused row per clip. The
    -- "used" rows are picked per user until SwipeTarget is reached and get a
    -- recency-biased timestamp between the purchase date and @Now.
    -------------------------------------------------------------------------
    ;WITH nums AS
    (
        SELECT TOP (50) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS j
        FROM sys.all_objects
    )
    INSERT INTO dbo.Tickets
        (DateCreated, DateUsed, ProductId, IsUsed, Status, [Owner_Id], [Purchase_Id], UsedOnMenuItemId)
    SELECT
        pp.DateCreated,
        NULL,
        pp.ProductId,
        0,
        2,
        u.Id,
        pp.Id,
        NULL
    FROM #PurchasePlan pp
    INNER JOIN #SeedUserIds u ON u.Email = pp.Email
    INNER JOIN nums n ON n.j <= pp.NumberOfTickets
    WHERE pp.PurchaseStatus = N'Refunded';

    ;WITH nums AS
    (
        SELECT TOP (50) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS j
        FROM sys.all_objects
    )
    INSERT INTO dbo.Tickets
        (DateCreated, DateUsed, ProductId, IsUsed, Status, [Owner_Id], [Purchase_Id], UsedOnMenuItemId)
    SELECT
        pp.DateCreated,
        NULL,
        pp.ProductId,
        0,
        0,
        u.Id,
        pp.Id,
        NULL
    FROM #PurchasePlan pp
    INNER JOIN #SeedUserIds u ON u.Email = pp.Email
    INNER JOIN nums n ON n.j <= pp.NumberOfTickets
    WHERE pp.PurchaseStatus = N'Completed';

    ;WITH candidates AS
    (
        SELECT
            t.Id,
            t.[Owner_Id],
            ROW_NUMBER() OVER (PARTITION BY t.[Owner_Id] ORDER BY NEWID()) AS rn
        FROM dbo.Tickets t
        INNER JOIN dbo.Purchases p ON p.Id = t.[Purchase_Id]
        WHERE t.Status = 0
          AND p.Status = N'Completed'
          AND p.Price > 0
          -- Leave today's purchases untouched so the tickets screen has
          -- unused clips bought today (and so "today" does not swallow a
          -- third of the whole history).
          AND CAST(p.DateCreated AS DATE) < CAST(@Now AS DATE)
    )
    UPDATE t
    SET t.Status = 1,
        t.IsUsed = 1,
        t.DateUsed = dt.DateUsed,
        t.UsedOnMenuItemId = mi.MenuItemId
    FROM dbo.Tickets t
    INNER JOIN candidates c ON c.Id = t.Id
    INNER JOIN #SeedUserIds u ON u.Id = t.[Owner_Id]
    INNER JOIN @SeedUsers su ON su.Email = u.Email
    INNER JOIN dbo.Purchases p ON p.Id = t.[Purchase_Id]
    CROSS APPLY
    (
        SELECT ABS(CHECKSUM(NEWID(), t.Id)) AS Roll
    ) rnd
    CROSS APPLY
    (
        SELECT CAST(DATEDIFF(day, p.DateCreated, @Now) AS INT) AS AgeDays
    ) a
    CROSS APPLY
    (
        SELECT CASE
            WHEN a.AgeDays <= 1 THEN 1
            ELSE 1 + CAST((rnd.Roll % 1000) / 1000.0 * (a.AgeDays - 1) AS INT)
        END AS OffsetDays
    ) o
    CROSS APPLY
    (
        SELECT ABS(CHECKSUM(NEWID(), t.Id, 7)) % 600 AS MinuteOfDay
    ) rnd2
    CROSS APPLY
    (
        SELECT DATEADD(
                   minute,
                   rnd2.MinuteOfDay,
                   DATEADD(hour, 7, CAST(CAST(DATEADD(day, -o.OffsetDays, @Now) AS DATE) AS DATETIME2))
               ) AS Candidate
    ) c2
    CROSS APPLY
    (
        SELECT CASE
            WHEN c2.Candidate > @Now THEN DATEADD(minute, 30, p.DateCreated)
            WHEN c2.Candidate < p.DateCreated THEN DATEADD(minute, 30, p.DateCreated)
            ELSE c2.Candidate
        END AS DateUsed
    ) dt
    CROSS APPLY
    (
        SELECT TOP (1) mp.MenuItemId
        FROM dbo.MenuItemProducts mp
        WHERE mp.ProductId = t.ProductId
        ORDER BY ABS(CHECKSUM(NEWID(), t.Id, mp.MenuItemId))
    ) mi
    WHERE c.rn <= su.SwipeTarget;

    -- Make sure a handful of swipes happened today, so "Cups drunk by ITU
    -- today" is never empty (unless the seed runs just after UTC midnight).
    ;WITH pick AS
    (
        SELECT
            t.Id,
            ROW_NUMBER() OVER (PARTITION BY t.[Owner_Id] ORDER BY NEWID()) AS rn
        FROM dbo.Tickets t
        INNER JOIN dbo.Purchases p ON p.Id = t.[Purchase_Id]
        INNER JOIN #SeedUserIds u ON u.Id = t.[Owner_Id]
        WHERE t.Status = 1
          AND p.Status = N'Completed'
          AND p.Price > 0
          AND p.DateCreated < DATEADD(hour, -2, @Now)
          AND u.Email IN
              (N'a@analog.local', N'b@analog.local', N'c@analog.local', N'd@analog.local',
               N'e@analog.local', N'f@analog.local', N'k@analog.local', N'q@analog.local',
               N'z@analog.local')
    )
    UPDATE t
    SET t.DateUsed = DATEADD(minute, -(10 + p.rn * 9), @Now)
    FROM dbo.Tickets t
    INNER JOIN pick p ON p.Id = t.Id
    WHERE p.rn = 1;

    -------------------------------------------------------------------------
    -- Keep Omid (#1) at the top of the month and semester leaderboards too,
    -- by re-dating a few of his older used tickets into the preset window.
    -- The other users' best scores are read first, so no one is ever ahead.
    -------------------------------------------------------------------------
    DECLARE @OmidId INT = (SELECT Id FROM #SeedUserIds WHERE Email = N'a@analog.local');

    DECLARE @SemesterMax INT = ISNULL((
        SELECT MAX(cnt) FROM (
            SELECT COUNT(*) AS cnt
            FROM dbo.Tickets
            WHERE Status = 1
              AND [Owner_Id] <> @OmidId
              AND DateUsed >= @SemesterStart
              AND DateUsed < @SemesterEnd
            GROUP BY [Owner_Id]
        ) x), 0);
    DECLARE @SemesterTarget INT = CASE
        WHEN @SemesterMax + 5 > 85 THEN @SemesterMax + 5
        ELSE 85
    END;
    DECLARE @OmidSemester INT = (
        SELECT COUNT(*)
        FROM dbo.Tickets
        WHERE Status = 1 AND [Owner_Id] = @OmidId
          AND DateUsed >= @SemesterStart AND DateUsed < @SemesterEnd);

    -- Early January can fall before the spring semester start; skip the
    -- semester boost in that window (the semester has no swipes yet).
    IF @Now > @SemesterStart AND @OmidSemester < @SemesterTarget
    BEGIN
        ;WITH picks AS
        (
            SELECT t.Id, ROW_NUMBER() OVER (ORDER BY NEWID()) AS rn
            FROM dbo.Tickets t
            WHERE t.Status = 1
              AND t.[Owner_Id] = @OmidId
              AND t.DateUsed < @SemesterStart
        )
        UPDATE t
        SET t.DateUsed = CASE
            WHEN c.Candidate > @Now
                THEN DATEADD(minute, -(5 + ABS(CHECKSUM(NEWID(), t.Id, 13)) % 120), @Now)
            ELSE c.Candidate
        END
        FROM dbo.Tickets t
        INNER JOIN picks p ON p.Id = t.Id
        CROSS APPLY
        (
            SELECT DATEADD(
                       minute,
                       (ABS(CHECKSUM(NEWID(), t.Id, 17)) % (DATEDIFF(day, @SemesterStart, @Now) + 1)) * 1440
                       + ABS(CHECKSUM(NEWID(), t.Id, 19)) % 540 + 420,
                       @SemesterStart
                   ) AS Candidate
        ) c
        WHERE p.rn <= @SemesterTarget - @OmidSemester;
    END;

    DECLARE @MonthMax INT = ISNULL((
        SELECT MAX(cnt) FROM (
            SELECT COUNT(*) AS cnt
            FROM dbo.Tickets
            WHERE Status = 1
              AND [Owner_Id] <> @OmidId
              AND DateUsed >= @MonthStart
              AND DateUsed < DATEADD(month, 1, @MonthStart)
            GROUP BY [Owner_Id]
        ) x), 0);
    DECLARE @MonthTarget INT = CASE
        WHEN @MonthMax + 3 > 30 THEN @MonthMax + 3
        ELSE 30
    END;
    DECLARE @OmidMonth INT = (
        SELECT COUNT(*)
        FROM dbo.Tickets
        WHERE Status = 1 AND [Owner_Id] = @OmidId
          AND DateUsed >= @MonthStart AND DateUsed < DATEADD(month, 1, @MonthStart));

    IF @OmidMonth < @MonthTarget
    BEGIN
        ;WITH picks AS
        (
            SELECT t.Id, ROW_NUMBER() OVER (ORDER BY NEWID()) AS rn
            FROM dbo.Tickets t
            WHERE t.Status = 1
              AND t.[Owner_Id] = @OmidId
              AND t.DateUsed < @MonthStart
        )
        UPDATE t
        SET t.DateUsed = CASE
            WHEN c.Candidate > @Now
                THEN DATEADD(minute, -(5 + ABS(CHECKSUM(NEWID(), t.Id, 29)) % 60), @Now)
            ELSE c.Candidate
        END
        FROM dbo.Tickets t
        INNER JOIN picks p ON p.Id = t.Id
        CROSS APPLY
        (
            SELECT DATEADD(
                       minute,
                       (ABS(CHECKSUM(NEWID(), t.Id, 31)) % (DATEDIFF(day, @MonthStart, @Now) + 1)) * 1440
                       + ABS(CHECKSUM(NEWID(), t.Id, 37)) % 540 + 420,
                       @MonthStart
                   ) AS Candidate
        ) c
        WHERE p.rn <= @MonthTarget - @OmidMonth;
    END;

    -------------------------------------------------------------------------
    -- Vouchers: one per completed voucher purchase, plus a few unredeemed
    -- codes for exercising the redeem-voucher screen.
    -------------------------------------------------------------------------
    INSERT INTO dbo.Vouchers
        (Code, DateCreated, DateUsed, Description, Requester, [Product_Id], [User_Id], PurchaseId)
    SELECT
        N'SEED-VOUCHER-' + RIGHT(N'0000' + CAST(ROW_NUMBER() OVER (ORDER BY pp.PurchaseKey) AS NVARCHAR(4)), 4),
        pp.DateCreated,
        pp.DateCreated,
        N'Voucher redeemed during seeding',
        N'Analog',
        pp.ProductId,
        u.Id,
        pp.Id
    FROM #PurchasePlan pp
    INNER JOIN #SeedUserIds u ON u.Email = pp.Email
    WHERE pp.PurchaseType = N'Voucher'
      AND pp.PurchaseStatus = N'Completed';

    INSERT INTO dbo.Vouchers
        (Code, DateCreated, DateUsed, Description, Requester, [Product_Id], [User_Id], PurchaseId)
    SELECT
        v.Code,
        DATEADD(day, -v.DaysAgo, @Now),
        NULL,
        v.Description,
        N'Analog',
        l.Id,
        NULL,
        NULL
    FROM (VALUES
        (N'SEED-GIFT-COFFEE', 3,  N'Coffee voucher for the redeem screen', N'Small'),
        (N'SEED-GIFT-TEA',    8,  N'Tea voucher for the redeem screen', N'Tea'),
        (N'SEED-GIFT-ICED',   12, N'Iced coffee voucher for the redeem screen', N'Iced'),
        (N'SEED-GIFT-HOTCHOC', 20, N'Hot chocolate voucher for the redeem screen', N'Hot Chocolate')
    ) v(Code, DaysAgo, Description, ProductName)
    INNER JOIN @ProductLookup l ON l.Name = v.ProductName;

    -------------------------------------------------------------------------
    -- Point-of-sale rows for purchases issued by a barista.
    -------------------------------------------------------------------------
    INSERT INTO dbo.PosPurchases (PurchaseId, BaristaInitials)
    SELECT
        pp.Id,
        CASE ABS(CHECKSUM(pp.PurchaseKey)) % 3
            WHEN 0 THEN N'ER'
            WHEN 1 THEN N'NC'
            ELSE N'IM'
        END
    FROM #PurchasePlan pp
    WHERE pp.PurchaseType = N'PointOfSale';

    -------------------------------------------------------------------------
    -- Statistics (leaderboard): one row per preset for every user with at
    -- least one paid swipe. Only paid purchases count, matching the app.
    -------------------------------------------------------------------------
    ;WITH paid AS
    (
        SELECT t.[Owner_Id] AS UserId, t.DateUsed
        FROM dbo.Tickets t
        INNER JOIN dbo.Purchases p ON p.Id = t.[Purchase_Id]
        INNER JOIN #SeedUserIds u ON u.Id = t.[Owner_Id]
        WHERE t.Status = 1 AND p.Price > 0
    )
    INSERT INTO dbo.[Statistics] (Preset, SwipeCount, LastSwipe, ExpiryDate, [User_Id])
    SELECT
        0,
        COUNT(CASE WHEN DateUsed >= @MonthStart AND DateUsed < DATEADD(month, 1, @MonthStart) THEN 1 END),
        MAX(DateUsed),
        @MonthEnd,
        UserId
    FROM paid
    GROUP BY UserId
    UNION ALL
    SELECT
        1,
        COUNT(CASE WHEN DateUsed >= @SemesterStart AND DateUsed < @SemesterEnd THEN 1 END),
        MAX(DateUsed),
        @SemesterEnd,
        UserId
    FROM paid
    GROUP BY UserId
    UNION ALL
    SELECT
        2,
        COUNT(*),
        MAX(DateUsed),
        DATEADD(year, 100, @Now),
        UserId
    FROM paid
    GROUP BY UserId;

    -- Guard: this seed must never leave "DUMMY" names behind.
    IF EXISTS (SELECT 1 FROM dbo.Programmes WHERE ShortName = N'DUMMY' OR FullName LIKE N'%Dummy%')
        THROW 51000, 'Seed left a DUMMY programme behind.', 1;

    IF EXISTS (SELECT 1 FROM dbo.Products WHERE Name LIKE N'Dummy Seed%')
        THROW 51001, 'Seed left DUMMY product names behind.', 1;

    IF EXISTS (SELECT 1 FROM dbo.MenuItems WHERE Name LIKE N'Dummy Seed%')
        THROW 51002, 'Seed left DUMMY menu item names behind.', 1;

    COMMIT TRANSACTION;

    SELECT
        (SELECT COUNT(*) FROM dbo.Users WHERE Email LIKE N'_@analog.local') AS SeededUsers,
        (SELECT COUNT(*) FROM dbo.Programmes) AS Programmes,
        (SELECT COUNT(*) FROM dbo.Products) AS Products,
        (SELECT COUNT(*) FROM dbo.MenuItems) AS MenuItems,
        (SELECT COUNT(*) FROM dbo.Purchases) AS Purchases,
        (SELECT COUNT(*) FROM dbo.Tickets WHERE Status = 1) AS UsedTickets,
        (SELECT COUNT(*) FROM dbo.Tickets WHERE Status = 0) AS UnusedTickets,
        (SELECT COUNT(*) FROM dbo.Tickets WHERE Status = 2) AS RefundedTickets,
        (SELECT COUNT(*) FROM dbo.Tickets WHERE Status = 1 AND CAST(DateUsed AS DATE) = CAST(@Now AS DATE)) AS SwipesToday;

    SELECT TOP (10) u.Name, u.Email, s.SwipeCount
    FROM dbo.[Statistics] s
    INNER JOIN dbo.Users u ON u.Id = s.[User_Id]
    WHERE s.Preset = 2
    ORDER BY s.SwipeCount DESC, s.LastSwipe ASC;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
    BEGIN
        ROLLBACK TRANSACTION;
    END;

    THROW;
END CATCH;
