package main

import (
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
)

// User 用户模型
type User struct {
	ID           uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	Username     string    `gorm:"type:varchar(32);unique;not null"`
	PasswordHash string    `gorm:"type:varchar(255);not null"`
	Email        string    `gorm:"type:varchar(255);unique"`
	Nickname     string    `gorm:"type:varchar(64)"`
	LastIPv6     string    `gorm:"type:inet"`
	IPv6Verified bool      `gorm:"default:false"`
	Status       int16     `gorm:"default:1"`
	CreatedAt    time.Time
	UpdatedAt    time.Time
	LastLoginAt  *time.Time
}

// Device 设备模型
type Device struct {
	ID            uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	UserID        uuid.UUID `gorm:"type:uuid;not null"`
	DeviceID      string    `gorm:"type:varchar(64);not null"`
	DeviceName    string    `gorm:"type:varchar(128)"`
	DeviceType    string    `gorm:"type:varchar(32)"`
	SupportsIPv6  bool      `gorm:"default:true"`
	LastIP        string    `gorm:"type:inet"`
	LastIPv6      string    `gorm:"type:inet"`
	LastSeenAt    *time.Time
	IsOnline      bool `gorm:"default:false"`
	CreatedAt     time.Time
	User          User `gorm:"foreignKey:UserID"`
}

// Session 会话模型
type Session struct {
	ID                uuid.UUID `gorm:"type:uuid;primary_key;default:gen_random_uuid()"`
	UserID            uuid.UUID `gorm:"type:uuid;not null"`
	DeviceID          string    `gorm:"type:varchar(64)"`
	AccessTokenHash   string    `gorm:"type:varchar(255);not null"`
	RefreshTokenHash  string    `gorm:"type:varchar(255);not null"`
	IP                string    `gorm:"type:inet"`
	IPv6              string    `gorm:"type:inet"`
	UserAgent         string    `gorm:"type:text"`
	ExpiresAt         time.Time `gorm:"not null"`
	CreatedAt         time.Time
	RevokedAt         *time.Time
	User              User `gorm:"foreignKey:UserID"`
}

// BeforeCreate 钩子：自动生成 UUID
func (u *User) BeforeCreate(tx *gorm.DB) error {
	if u.ID == uuid.Nil {
		u.ID = uuid.New()
	}
	return nil
}

func (d *Device) BeforeCreate(tx *gorm.DB) error {
	if d.ID == uuid.Nil {
		d.ID = uuid.New()
	}
	return nil
}

func (s *Session) BeforeCreate(tx *gorm.DB) error {
	if s.ID == uuid.Nil {
		s.ID = uuid.New()
	}
	return nil
}

// ICETelemetry 连接信息上报
type ICETelemetry struct {
	Version     int               `json:"version"`
	Type        string            `json:"type"`
	Timestamp   int64             `json:"timestamp"`
	UserID      string            `json:"user_id"`
	DeviceID    string            `json:"device_id"`
	SessionInfo SessionInfo       `json:"session_info"`
	Candidates  ICECandidates     `json:"ice_candidates"`
	ConnState   ConnectionState   `json:"connection_state"`
	Metrics     ConnectionMetrics `json:"metrics"`
	Errors      []ICEError        `json:"errors"`
}

type SessionInfo struct {
	SessionID string `json:"session_id"`
	PeerID    string `json:"peer_id"`
	Direction string `json:"direction"`
}

type ICECandidates struct {
	Local  []Candidate `json:"local"`
	Remote []Candidate `json:"remote"`
}

type Candidate struct {
	Type           string `json:"type"`
	Protocol       string `json:"protocol"`
	Address        string `json:"address"`
	Port           int    `json:"port"`
	Priority       int64  `json:"priority"`
	RelatedAddress string `json:"related_address,omitempty"`
	RelatedPort    int    `json:"related_port,omitempty"`
}

type ConnectionState struct {
	ICEConnectionState   string        `json:"ice_connection_state"`
	ConnectionState      string        `json:"connection_state"`
	SelectedCandidatePair CandidatePair `json:"selected_candidate_pair"`
}

type CandidatePair struct {
	Local  string `json:"local"`
	Remote string `json:"remote"`
	State  string `json:"state"`
}

type ConnectionMetrics struct {
	RTTMs           int   `json:"rtt_ms"`
	BytesSent       int64 `json:"bytes_sent"`
	BytesReceived   int64 `json:"bytes_received"`
	PacketsSent     int64 `json:"packets_sent"`
	PacketsReceived int64 `json:"packets_received"`
	PacketsLost     int64 `json:"packets_lost"`
}

type ICEError struct {
	Code      int    `json:"code"`
	Message   string `json:"message"`
	URL       string `json:"url"`
	Timestamp int64  `json:"timestamp"`
}

// ErrorLog 错误日志
type ErrorLog struct {
	Version      int                    `json:"version"`
	Type         string                 `json:"type"`
	Timestamp    int64                  `json:"timestamp"`
	TraceID      string                 `json:"trace_id"`
	SpanID       string                 `json:"span_id"`
	ParentSpanID string                 `json:"parent_span_id"`
	UserID       string                 `json:"user_id"`
	DeviceID     string                 `json:"device_id"`
	SessionID    string                 `json:"session_id"`
	Error        ErrorDetail            `json:"error"`
	Context      map[string]interface{} `json:"context"`
	Severity     string                 `json:"severity"`
	SampleRate   float64                `json:"sample_rate"`
}

type ErrorDetail struct {
	Code       string `json:"code"`
	Message    string `json:"message"`
	StackTrace string `json:"stack_trace"`
}
