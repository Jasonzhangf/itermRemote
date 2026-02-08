package main

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
)

// HandleICETelemetry 处理ICE连接信息上报
func HandleICETelemetry(c *gin.Context) {
	claims := c.MustGet("claims").(*Claims)

	var telemetry ICETelemetry
	if err := c.ShouldBindJSON(&telemetry); err != nil {
		c.JSON(400, gin.H{"error": "invalid payload"})
		return
	}

	// 设置用户ID
	telemetry.UserID = claims.UserID
	if telemetry.DeviceID == "" {
		telemetry.DeviceID = claims.DeviceID
	}

	// 异步存储到数据库
	go storeICETelemetry(&telemetry)

	// 更新Redis实时统计
	go updateICERealtimeStats(&telemetry)

	c.JSON(200, gin.H{"status": "accepted"})
}

func storeICETelemetry(t *ICETelemetry) {
	// 转换候选者为JSON
	localCandidates, _ := json.Marshal(t.Candidates.Local)
	remoteCandidates, _ := json.Marshal(t.Candidates.Remote)
	selectedPair, _ := json.Marshal(t.ConnState.SelectedCandidatePair)
	errors, _ := json.Marshal(t.Errors)

	record := map[string]interface{}{
		"id":                       uuid.New(),
		"user_id":                  t.UserID,
		"device_id":                t.DeviceID,
		"session_id":               t.SessionInfo.SessionID,
		"peer_id":                  t.SessionInfo.PeerID,
		"direction":                t.SessionInfo.Direction,
		"ice_connection_state":     t.ConnState.ICEConnectionState,
		"connection_state":         t.ConnState.ConnectionState,
		"rtt_ms":                   t.Metrics.RTTMs,
		"bytes_sent":               t.Metrics.BytesSent,
		"bytes_received":           t.Metrics.BytesReceived,
		"packets_sent":             t.Metrics.PacketsSent,
		"packets_received":         t.Metrics.PacketsReceived,
		"packets_lost":             t.Metrics.PacketsLost,
		"local_candidates":         localCandidates,
		"remote_candidates":        remoteCandidates,
		"selected_candidate_pair":  selectedPair,
		"errors":                   errors,
	}

	db.Table("ice_telemetry").Create(record)
}

func updateICERealtimeStats(t *ICETelemetry) {
	// 更新用户实时统计
	key := "ice:stats:" + t.UserID + ":" + t.SessionInfo.SessionID
	data := map[string]interface{}{
		"connection_state": t.ConnState.ICEConnectionState,
		"rtt_ms":          t.Metrics.RTTMs,
		"updated_at":      time.Now().Unix(),
	}
	redisClient.HSet(ctx, key, data)
	redisClient.Expire(ctx, key, 24*time.Hour)

	// 更新全局统计
	if t.ConnState.ICEConnectionState == "connected" {
		redisClient.Incr(ctx, "ice:connected:total")
	}
	if len(t.Errors) > 0 {
		redisClient.Incr(ctx, "ice:errors:total")
	}
}
