-- 手機名片 App 資料庫設計 (Supabase 版本 - 不使用 RLS)
-- 版本：users.skill 改為 VARCHAR(255)

-- 清除舊表 (依相依順序)
DROP TABLE IF EXISTS conversation_records CASCADE;
DROP TABLE IF EXISTS contact_profiles CASCADE;
DROP TABLE IF EXISTS contacts CASCADE;
DROP TABLE IF EXISTS social_links CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- 1. 使用者表 (一位用戶一張名片)
CREATE TABLE users (
    user_id BIGSERIAL PRIMARY KEY,
    account VARCHAR(255) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL,
    avatar_url VARCHAR(255),
    username VARCHAR(255) NOT NULL,
    company VARCHAR(255),
    job_title VARCHAR(255),
    skill VARCHAR(255), -- 改為單純文字
    email VARCHAR(255),
    phone VARCHAR(255),
    qr_code_url VARCHAR(255) UNIQUE DEFAULT gen_random_uuid()::text,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. 社群媒體連結表
CREATE TABLE social_links (
    link_id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    platform VARCHAR(50) NOT NULL,
    url VARCHAR(500) NOT NULL,
    display_name VARCHAR(255),
    display_order INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. 聯絡人關係表
CREATE TABLE contacts (
    contact_id BIGSERIAL PRIMARY KEY,
    requester_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    friend_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT check_not_self CHECK (requester_id != friend_id)
);

-- 3.1 聯絡人個人化資訊表
CREATE TABLE contact_profiles (
    profile_id BIGSERIAL PRIMARY KEY,
    contact_id BIGINT NOT NULL REFERENCES contacts(contact_id) ON DELETE CASCADE,
    owner_id BIGINT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
    nickname VARCHAR(255),
    note VARCHAR(500),
    tags JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT unique_contact_owner UNIQUE (contact_id, owner_id)
);

-- 4. 對話記錄表
CREATE TABLE conversation_records (
    record_id BIGSERIAL PRIMARY KEY,
    contact_id BIGINT NOT NULL REFERENCES contacts(contact_id) ON DELETE CASCADE,
    event_name VARCHAR(255),
    content TEXT,
    summary VARCHAR(1000),
    audio_url VARCHAR(500),
    audio_duration INTEGER,
    location_name VARCHAR(255),
    latitude DECIMAL(10, 8),
    longitude DECIMAL(11, 8),
    location_type VARCHAR(20) DEFAULT 'physical',
    record_time TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 索引
CREATE INDEX idx_social_links_user_id ON social_links(user_id);
CREATE INDEX idx_social_links_display_order ON social_links(user_id, display_order);
CREATE INDEX idx_contacts_requester_id ON contacts(requester_id);
CREATE INDEX idx_contacts_friend_id ON contacts(friend_id);
CREATE INDEX idx_contacts_status ON contacts(status);
CREATE UNIQUE INDEX idx_unique_contact_pair ON contacts (
    LEAST(requester_id, friend_id), 
    GREATEST(requester_id, friend_id)
);
CREATE INDEX idx_contact_profiles_contact_id ON contact_profiles(contact_id);
CREATE INDEX idx_contact_profiles_owner_id ON contact_profiles(owner_id);
CREATE INDEX idx_conversation_records_contact_id ON conversation_records(contact_id);
CREATE INDEX idx_conversation_records_created_at ON conversation_records(created_at DESC);
CREATE INDEX idx_conversation_records_location ON conversation_records(latitude, longitude) WHERE latitude IS NOT NULL;

-- 自動更新 updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_users_updated_at 
    BEFORE UPDATE ON users 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_contacts_updated_at 
    BEFORE UPDATE ON contacts 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_contact_profiles_updated_at 
    BEFORE UPDATE ON contact_profiles 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_conversation_records_updated_at 
    BEFORE UPDATE ON conversation_records 
    FOR EACH ROW 
    EXECUTE FUNCTION update_updated_at_column();

-- 視圖
DROP VIEW IF EXISTS user_complete_profile;
CREATE VIEW user_complete_profile AS
SELECT 
    u.*,
    COALESCE(
        json_agg(
            json_build_object(
                'link_id', sl.link_id,
                'platform', sl.platform,
                'url', sl.url,
                'display_name', sl.display_name,
                'display_order', sl.display_order,
                'is_active', sl.is_active
            ) ORDER BY sl.display_order
        ) FILTER (WHERE sl.link_id IS NOT NULL), 
        '[]'::json
    ) as social_links
FROM users u
LEFT JOIN social_links sl ON u.user_id = sl.user_id AND sl.is_active = true
GROUP BY u.user_id;

DROP VIEW IF EXISTS contact_relationships;
CREATE VIEW contact_relationships AS
SELECT 
    c.contact_id,
    c.requester_id,
    c.friend_id,
    c.status,
    c.created_at,
    c.updated_at,
    ru.username as requester_username,
    ru.company as requester_company,
    ru.job_title as requester_job_title,
    ru.avatar_url as requester_avatar,
    fu.username as friend_username,
    fu.company as friend_company,
    fu.job_title as friend_job_title,
    fu.avatar_url as friend_avatar,
    rp.nickname as requester_set_nickname,
    rp.note as requester_set_note,
    rp.tags as requester_set_tags,
    fp.nickname as friend_set_nickname,
    fp.note as friend_set_note,
    fp.tags as friend_set_tags
FROM contacts c
JOIN users ru ON c.requester_id = ru.user_id
JOIN users fu ON c.friend_id = fu.user_id
LEFT JOIN contact_profiles rp ON c.contact_id = rp.contact_id AND rp.owner_id = c.requester_id
LEFT JOIN contact_profiles fp ON c.contact_id = fp.contact_id AND fp.owner_id = c.friend_id;

DROP VIEW IF EXISTS conversation_records_complete;
CREATE VIEW conversation_records_complete AS
SELECT 
    cr.*,
    c.requester_id,
    c.friend_id,
    c.status as contact_status,
    ru.username as requester_username,
    ru.avatar_url as requester_avatar,
    fu.username as friend_username,
    fu.avatar_url as friend_avatar
FROM conversation_records cr
JOIN contacts c ON cr.contact_id = c.contact_id
JOIN users ru ON c.requester_id = ru.user_id
JOIN users fu ON c.friend_id = fu.user_id;

-- 插入測試資料範例
/*
-- 測試用戶
INSERT INTO users (account, password, username, company, job_title, email, phone, skill) VALUES
('john.doe@email.com', 'hashed_password_1', 'John Doe', 'Tech Corp', 'Software Engineer', 'john.doe@email.com', '+886-912-345-678', 'Go, PostgreSQL, Kubernetes'),
('jane.smith@email.com', 'hashed_password_2', 'Jane Smith', 'Design Studio', 'UI/UX Designer', 'jane.smith@email.com', '+886-923-456-789', 'Figma, UI/UX, Prototyping'),
('bob.wilson@email.com', 'hashed_password_3', 'Bob Wilson', 'Marketing Inc', 'Marketing Manager', 'bob.wilson@email.com', '+886-934-567-890', 'SEO, Content Marketing, Analytics');

-- 測試社群連結
INSERT INTO social_links (user_id, platform, url, display_name, display_order) VALUES
(1, 'linkedin', 'https://linkedin.com/in/johndoe', 'John Doe', 0),
(1, 'github', 'https://github.com/johndoe', '@johndoe', 0),
(1, 'website', 'https://johndoe.dev', 'johndoe.dev', 0),
(2, 'instagram', 'https://instagram.com/janesmith', '@janesmith', 0),
(2, 'linkedin', 'https://linkedin.com/in/janesmith', 'Jane Smith', 0),
(3, 'facebook', 'https://facebook.com/bobwilson', 'Bob Wilson', 0);

-- 測試聯絡人關係
INSERT INTO contacts (requester_id, friend_id, status) VALUES
(1, 2, 'accepted'),
(1, 3, 'pending'),
(2, 3, 'accepted');

-- 雙方互相設定暱稱和備註
INSERT INTO contact_profiles (contact_id, owner_id, nickname, note, tags) VALUES
-- John 對 Jane 的設定
(1, 1, 'Jane 設計師', '合作夥伴，設計能力很強', '["設計師", "合作夥伴"]'),
-- Jane 對 John 的設定  
(1, 2, 'John 工程師', '技術很好的後端工程師', '["工程師", "後端"]'),
-- Jane 對 Bob 的設定
(3, 2, 'Bob 行銷', '行銷專家，很會做推廣', '["行銷", "客戶"]'),
-- Bob 對 Jane 的設定
(3, 3, 'Jane 美女設計師', '設計超棒的夥伴', '["設計師", "美女"]');

-- 測試對話記錄
INSERT INTO conversation_records (contact_id, event_name, content, summary, audio_url, location_name, latitude, longitude, record_time) VALUES
(1, '專案討論會議', '今天我們討論了新專案的方向，包括技術架構和設計風格...', '討論新專案方向和合作細節', 'https://storage.supabase.co/audio/meeting_20240101.mp3', '台北101咖啡廳', 25.0338, 121.5645, '2024-01-01 14:00:00+08'),
(3, '行銷策略會議', '我們聊了新產品的行銷策略，包括目標客群和推廣管道...', '制定新產品行銷策略', 'https://storage.supabase.co/audio/marketing_20240102.mp3', '信義區星巴克', 25.0330, 121.5654, '2024-01-02 10:30:00+08');
*/

-- 常用查詢範例
/*
-- 查詢用戶完整資訊 (包含社群連結)
SELECT * FROM user_complete_profile WHERE user_id = 1;

-- 查詢某用戶的所有聯絡人 (已接受的)
SELECT * FROM contact_relationships 
WHERE (requester_id = 1 OR friend_id = 1) AND status = 'accepted';

-- 查詢某用戶的待處理邀請
SELECT * FROM contact_relationships 
WHERE friend_id = 1 AND status = 'pending';

-- 查詢某用戶發出的邀請
SELECT * FROM contact_relationships 
WHERE requester_id = 1 AND status = 'pending';

-- 查詢兩個用戶間的對話記錄
SELECT * FROM conversation_records_complete cr
WHERE (cr.requester_id = 1 AND cr.friend_id = 2) 
   OR (cr.requester_id = 2 AND cr.friend_id = 1)
ORDER BY cr.record_time DESC;
*/