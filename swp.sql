-- =====================
-- 1. Users Table
-- =====================
CREATE TABLE Users (
    user_id INT PRIMARY KEY IDENTITY(1,1),
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone VARCHAR(20),
    role VARCHAR(10) NOT NULL CHECK (role IN ('admin', 'donor', 'recipient', 'staff')),
    status VARCHAR(10) DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
    created_at DATETIME DEFAULT GETDATE()
);

-- =====================
-- 2. UserRoles & Assignments
-- =====================
CREATE TABLE UserRoles (
    role_id INT PRIMARY KEY IDENTITY(1,1),
    role_name VARCHAR(50) UNIQUE NOT NULL,
    description TEXT
);

CREATE TABLE UserRoleAssignments (
    assignment_id INT PRIMARY KEY IDENTITY(1,1),
    user_id INT NOT NULL,
    role_id INT NOT NULL,
    assigned_date DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (user_id) REFERENCES Users(user_id),
    FOREIGN KEY (role_id) REFERENCES UserRoles(role_id)
);

-- =====================
-- 3. BloodGroups
-- =====================
CREATE TABLE BloodGroups (
    blood_group_id INT PRIMARY KEY IDENTITY(1,1),
    blood_type VARCHAR(2) NOT NULL CHECK (blood_type IN ('A', 'B', 'AB', 'O')),
    rh_factor VARCHAR(1) NOT NULL CHECK (rh_factor IN ('+', '-'))
);

-- =====================
-- 4. Components
-- =====================
CREATE TABLE Components (
    component_id INT PRIMARY KEY IDENTITY(1,1),
    component_name VARCHAR(100) NOT NULL, -- e.g., Whole Blood, Plasma, Platelets
    description TEXT
);

-- =====================
-- 5. Donors
-- =====================
CREATE TABLE Donors (
    donor_id INT PRIMARY KEY IDENTITY(1,1),
    user_id INT UNIQUE NOT NULL,
    blood_group_id INT NOT NULL,
    date_of_birth DATE,
    gender VARCHAR(10) CHECK (gender IN ('male', 'female', 'other')),
    address TEXT,
    last_donation_date DATE,
    FOREIGN KEY (user_id) REFERENCES Users(user_id),
    FOREIGN KEY (blood_group_id) REFERENCES BloodGroups(blood_group_id)
);

-- =====================
-- 6. Recipients
-- =====================
CREATE TABLE Recipients (
    recipient_id INT PRIMARY KEY IDENTITY(1,1),
    user_id INT UNIQUE NOT NULL,
    blood_group_id INT NOT NULL,
    date_of_birth DATE,
    gender VARCHAR(10) CHECK (gender IN ('male', 'female', 'other')),
    address TEXT,
    medical_condition TEXT,
    FOREIGN KEY (user_id) REFERENCES Users(user_id),
    FOREIGN KEY (blood_group_id) REFERENCES BloodGroups(blood_group_id)
);

-- =====================
-- 7. BloodBags
-- =====================
CREATE TABLE BloodBags (
    blood_bag_id INT PRIMARY KEY IDENTITY(1,1),
    donor_id INT NOT NULL,
    blood_group_id INT NOT NULL,
    component_id INT NOT NULL,
    volume_ml INT NOT NULL,
    collection_date DATE NOT NULL,
    expiry_date DATE NOT NULL,
    status VARCHAR(10) DEFAULT 'available' CHECK (status IN ('available', 'reserved', 'used', 'expired')),
    FOREIGN KEY (donor_id) REFERENCES Donors(donor_id),
    FOREIGN KEY (blood_group_id) REFERENCES BloodGroups(blood_group_id),
    FOREIGN KEY (component_id) REFERENCES Components(component_id)
);

-- =====================
-- 8. BloodRequests
-- =====================
CREATE TABLE BloodRequests (
    request_id INT PRIMARY KEY IDENTITY(1,1),
    recipient_id INT NOT NULL,
    blood_group_id INT NOT NULL,
    component_id INT NOT NULL,
    quantity INT NOT NULL,
    request_date DATE DEFAULT CAST(GETDATE() AS DATE),
    status VARCHAR(10) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'fulfilled')),
    FOREIGN KEY (recipient_id) REFERENCES Recipients(recipient_id),
    FOREIGN KEY (blood_group_id) REFERENCES BloodGroups(blood_group_id),
    FOREIGN KEY (component_id) REFERENCES Components(component_id)
);

-- =====================
-- 9. BloodIssuance
-- =====================
CREATE TABLE BloodIssuance (
    issuance_id INT PRIMARY KEY IDENTITY(1,1),
    request_id INT NOT NULL,
    blood_bag_id INT NOT NULL,
    issued_by INT NOT NULL,
    issued_date DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (request_id) REFERENCES BloodRequests(request_id),
    FOREIGN KEY (blood_bag_id) REFERENCES BloodBags(blood_bag_id),
    FOREIGN KEY (issued_by) REFERENCES Users(user_id)
);

-- =====================
-- 10. DonationAppointments
-- =====================
CREATE TABLE DonationAppointments (
    appointment_id INT PRIMARY KEY IDENTITY(1,1),
    donor_id INT NOT NULL,
    appointment_date DATETIME NOT NULL,
    status VARCHAR(10) DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'completed', 'cancelled')),
    FOREIGN KEY (donor_id) REFERENCES Donors(donor_id)
);

-- =====================
-- 11. DonationRecords
-- =====================
CREATE TABLE DonationRecords (
    donation_id INT PRIMARY KEY IDENTITY(1,1),
    donor_id INT NOT NULL,
    blood_bag_id INT NOT NULL,
    donation_date DATE NOT NULL,
    FOREIGN KEY (donor_id) REFERENCES Donors(donor_id),
    FOREIGN KEY (blood_bag_id) REFERENCES BloodBags(blood_bag_id)
);

-- =====================
-- 12. Inventory
-- =====================
CREATE TABLE Inventory (
    inventory_id INT PRIMARY KEY IDENTITY(1,1),
    blood_group_id INT NOT NULL,
    component_id INT NOT NULL,
    quantity INT DEFAULT 0,
    last_updated DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (blood_group_id) REFERENCES BloodGroups(blood_group_id),
    FOREIGN KEY (component_id) REFERENCES Components(component_id)
);

-- =====================
-- 13. DonationReminders
-- =====================
CREATE TABLE DonationReminders (
    reminder_id INT PRIMARY KEY IDENTITY(1,1),
    donor_id INT NOT NULL,
    next_donation_date DATE NOT NULL,
    reminder_date DATE NOT NULL,
    sent BIT DEFAULT 0,
    FOREIGN KEY (donor_id) REFERENCES Donors(donor_id)
);

-- =================================
-- 14. Procedure kiểm tra đủ điều kiện hiến máu
-- =================================
CREATE PROCEDURE CheckDonorEligibility
    @DonorId INT,
    @RequestedDate DATE,
    @IsEligible BIT OUTPUT,
    @NextEligibleDate DATE OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @MinRestDays INT = 84; -- Khoảng nghỉ giữa 2 lần hiến (ví dụ 84 ngày)
    DECLARE @LastDonationDate DATE;

    SELECT @LastDonationDate = last_donation_date
    FROM Donors
    WHERE donor_id = @DonorId;

    IF @LastDonationDate IS NULL
    BEGIN
        -- Chưa từng hiến lần nào => được phép hiến
        SET @IsEligible = 1;
        SET @NextEligibleDate = @RequestedDate;
        RETURN;
    END

    SET @NextEligibleDate = DATEADD(DAY, @MinRestDays, @LastDonationDate);

    IF @RequestedDate >= @NextEligibleDate
        SET @IsEligible = 1;
    ELSE
        SET @IsEligible = 0;
END

-- =================================
-- 15. Trigger cập nhật last_donation_date trong Donors sau khi hiến máu
-- =================================
CREATE TRIGGER trg_UpdateLastDonationDate
ON DonationRecords
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE d
    SET last_donation_date = i.donation_date
    FROM Donors d
    INNER JOIN inserted i ON d.donor_id = i.donor_id;
END

-- =================================
-- 16. Trigger tạo nhắc nhở hiến máu tiếp theo
-- =================================
CREATE TRIGGER trg_CreateDonationReminder
ON DonationRecords
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @MinRestDays INT = 84;
    DECLARE @ReminderAdvanceDays INT = 7; -- gửi nhắc nhở trước 7 ngày

    INSERT INTO DonationReminders (donor_id, next_donation_date, reminder_date, sent)
    SELECT
        i.donor_id,
        DATEADD(DAY, @MinRestDays, i.donation_date) AS next_donation_date,
        DATEADD(DAY, @MinRestDays - @ReminderAdvanceDays, i.donation_date) AS reminder_date,
        0
    FROM inserted i;
END

-- =================================
-- 17. Ví dụ gọi procedure kiểm tra điều kiện hiến máu
-- =================================
DECLARE @IsEligible BIT;
DECLARE @NextDate DATE;

EXEC CheckDonorEligibility @DonorId = 1, @RequestedDate = CAST(GETDATE() AS DATE),
                          @IsEligible = @IsEligible OUTPUT,
                          @NextEligibleDate = @NextDate OUTPUT;

IF @IsEligible = 1
    PRINT 'Bạn được phép đăng ký hiến máu ngày này.';
ELSE
    PRINT 'Bạn chưa đủ thời gian nghỉ giữa 2 lần hiến máu. Bạn có thể đăng ký hiến lại sau ngày: ' + CONVERT(VARCHAR, @NextDate, 23);
