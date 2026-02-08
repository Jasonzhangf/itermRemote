package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"
	"github.com/redis/go-redis/v9"
	"context"
)

var (
	upgrader = websocket.Upgrader{CheckOrigin: func(r *http.Request) bool { return true }}
	clients = make(map[string]*Client)
	clientsMux sync.RWMutex
	jwtSecret = []byte(getEnv("JWT_SECRET", "secret"))
	redisClient *redis.Client
	ctx = context.Background()
)

type Client struct {
	UserID string
	DeviceID string
	Conn *websocket.Conn
	Send chan []byte
}

type Claims struct {
	UserID string `json:"sub"`
	DeviceID string `json:"device_id"`
	jwt.RegisteredClaims
}

func main() {
	redisClient = redis.NewClient(&redis.Options{
		Addr: getEnv("REDIS_HOST", "localhost:6379"),
		Password: getEnv("REDIS_PASSWORD", ""),
	})
	
	http.HandleFunc("/ws/health", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(map[string]interface{}{"status": "ok", "clients": len(clients)})
	})
	http.HandleFunc("/ws/connect", handleWebSocket)
	
	port := getEnv("PORT", "8081")
	log.Printf("WS server on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}

func handleWebSocket(w http.ResponseWriter, r *http.Request) {
	token := r.URL.Query().Get("token")
	claims, err := validateToken(token)
	if err != nil {
		http.Error(w, "unauthorized", 401)
		return
	}
	
	conn, _ := upgrader.Upgrade(w, r, nil)
	client := &Client{UserID: claims.UserID, DeviceID: claims.DeviceID, Conn: conn, Send: make(chan []byte, 256)}
	
	clientsMux.Lock()
	clients[client.UserID] = client
	clientsMux.Unlock()
	
	redisClient.Set(ctx, "online:"+client.UserID, "true", 90*time.Second)
	
	go client.writePump()
	go client.readPump()
}

func (c *Client) readPump() {
	defer c.cleanup()
	c.Conn.SetReadDeadline(time.Now().Add(60*time.Second))
	c.Conn.SetPongHandler(func(string) error {
		c.Conn.SetReadDeadline(time.Now().Add(60*time.Second))
		redisClient.Set(ctx, "online:"+c.UserID, "true", 90*time.Second)
		return nil
	})
	
	for {
		_, _, err := c.Conn.ReadMessage()
		if err != nil {
			break
		}
	}
}

func (c *Client) writePump() {
	ticker := time.NewTicker(30*time.Second)
	defer ticker.Stop()
	
	for {
		select {
		case msg := <-c.Send:
			c.Conn.WriteMessage(websocket.TextMessage, msg)
		case <-ticker.C:
			c.Conn.WriteMessage(websocket.PingMessage, nil)
		}
	}
}

func (c *Client) cleanup() {
	clientsMux.Lock()
	delete(clients, c.UserID)
	clientsMux.Unlock()
	redisClient.Del(ctx, "online:"+c.UserID)
}

func validateToken(tokenString string) (*Claims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &Claims{}, func(t *jwt.Token) (interface{}, error) {
		return jwtSecret, nil
	})
	if err != nil { return nil, err }
	if claims, ok := token.Claims.(*Claims); ok && token.Valid {
		return claims, nil
	}
	return nil, jwt.ErrSignatureInvalid
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" { return v }
	return fallback
}
