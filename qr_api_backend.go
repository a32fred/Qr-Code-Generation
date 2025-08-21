package main

import (
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/go-redis/redis/v8"
	"github.com/skip2/go-qrcode"
	"github.com/stripe/stripe-go/v74"
	"github.com/stripe/stripe-go/v74/customer"
	_ "github.com/mattn/go-sqlite3"
	"golang.org/x/time/rate"
	"context"
)

type QRRequest struct {
	Data     string `json:"data" binding:"required"`
	Size     int    `json:"size"`
	Format   string `json:"format"`
	Color    string `json:"color"`
	BgColor  string `json:"bg_color"`
	Logo     string `json:"logo"` // base64 encoded
}

type QRResponse struct {
	QRCode    string `json:"qr_code"`    // base64 encoded
	QRUrl     string `json:"qr_url"`     // URL para download
	Analytics string `json:"analytics"`  // URL para analytics
}

type User struct {
	ID       int    `json:"id"`
	APIKey   string `json:"api_key"`
	Plan     string `json:"plan"`
	Usage    int    `json:"usage"`
	Limit    int    `json:"limit"`
	Created  time.Time `json:"created"`
}

type App struct {
	db    *sql.DB
	redis *redis.Client
	limiter map[string]*rate.Limiter
}

var plans = map[string]int{
	"free":     100,
	"starter":  2500,
	"pro":      10000,
	"business": 100000,
}

func main() {
	// Initialize Stripe
	stripe.Key = os.Getenv("STRIPE_SECRET_KEY")
	
	app := &App{
		limiter: make(map[string]*rate.Limiter),
	}
	
	// Connect to SQLite
	var err error
	app.db, err = sql.Open("sqlite3", "./qrapi.db")
	if err != nil {
		log.Fatal(err)
	}
	defer app.db.Close()
	
	// Connect to Redis
	app.redis = redis.NewClient(&redis.Options{
		Addr: "localhost:6379",
		DB:   0,
	})
	
	// Initialize database
	app.initDB()
	
	// Setup Gin
	r := gin.Default()
	
	// CORS middleware
	r.Use(func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Authorization, X-API-Key")
		
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		
		c.Next()
	})
	
	// Routes
	r.GET("/", app.handleHome)
	r.POST("/api/register", app.handleRegister)
	r.POST("/api/generate", app.authMiddleware(), app.handleGenerate)
	r.GET("/api/usage", app.authMiddleware(), app.handleUsage)
	r.POST("/api/webhook/stripe", app.handleStripeWebhook)
	r.GET("/qr/:id", app.handleQRView)
	r.GET("/analytics/:id", app.handleAnalytics)
	
	log.Println("QR API Server starting on :8080")
	r.Run(":8080")
}

func (app *App) initDB() {
	query := `
	CREATE TABLE IF NOT EXISTS users (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		api_key TEXT UNIQUE NOT NULL,
		plan TEXT DEFAULT 'free',
		stripe_customer_id TEXT,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP
	);
	
	CREATE TABLE IF NOT EXISTS qr_codes (
		id TEXT PRIMARY KEY,
		user_id INTEGER,
		data TEXT NOT NULL,
		scans INTEGER DEFAULT 0,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
		FOREIGN KEY (user_id) REFERENCES users (id)
	);`
	
	_, err := app.db.Exec(query)
	if err != nil {
		log.Fatal(err)
	}
}

func (app *App) handleHome(c *gin.Context) {
	c.JSON(200, gin.H{
		"service": "QR Code API",
		"version": "1.0",
		"docs": "https://qrapi.dev/docs",
		"pricing": map[string]interface{}{
			"free":     "100 QRs/month",
			"starter":  "$5/month - 2,500 QRs",
			"pro":      "$15/month - 10,000 QRs + features",
			"business": "$50/month - 100,000 QRs + everything",
		},
	})
}

func (app *App) handleRegister(c *gin.Context) {
	apiKey := generateAPIKey()
	
	// Create Stripe customer
	params := &stripe.CustomerParams{}
	stripeCustomer, err := customer.New(params)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to create customer"})
		return
	}
	
	_, err = app.db.Exec(
		"INSERT INTO users (api_key, stripe_customer_id) VALUES (?, ?)",
		apiKey, stripeCustomer.ID,
	)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to create user"})
		return
	}
	
	c.JSON(201, gin.H{
		"api_key": apiKey,
		"plan": "free",
		"limit": 100,
		"message": "Welcome! You have 100 free QR codes per month.",
	})
}

func (app *App) authMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		apiKey := c.GetHeader("X-API-Key")
		if apiKey == "" {
			c.JSON(401, gin.H{"error": "API key required"})
			c.Abort()
			return
		}
		
		user, err := app.getUserByAPIKey(apiKey)
		if err != nil {
			c.JSON(401, gin.H{"error": "Invalid API key"})
			c.Abort()
			return
		}
		
		// Rate limiting
		limiter := app.getLimiter(apiKey)
		if !limiter.Allow() {
			c.JSON(429, gin.H{"error": "Rate limit exceeded"})
			c.Abort()
			return
		}
		
		c.Set("user", user)
		c.Next()
	}
}

func (app *App) handleGenerate(c *gin.Context) {
	user := c.MustGet("user").(*User)
	
	var req QRRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(400, gin.H{"error": err.Error()})
		return
	}
	
	// Check usage limits
	usage, err := app.getMonthlyUsage(user.ID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to check usage"})
		return
	}
	
	limit := plans[user.Plan]
	if usage >= limit {
		c.JSON(429, gin.H{
			"error": "Monthly limit exceeded",
			"usage": usage,
			"limit": limit,
			"upgrade_url": "https://qrapi.dev/upgrade",
		})
		return
	}
	
	// Set defaults
	if req.Size == 0 {
		req.Size = 256
	}
	if req.Format == "" {
		req.Format = "png"
	}
	if req.Color == "" {
		req.Color = "#000000"
	}
	if req.BgColor == "" {
		req.BgColor = "#FFFFFF"
	}
	
	// Generate QR Code
	qrID := generateID()
	qrCode, err := app.generateQR(req, user.Plan)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to generate QR code"})
		return
	}
	
	// Save to database
	_, err = app.db.Exec(
		"INSERT INTO qr_codes (id, user_id, data) VALUES (?, ?, ?)",
		qrID, user.ID, req.Data,
	)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to save QR code"})
		return
	}
	
	// Increment usage
	app.incrementUsage(user.ID)
	
	response := QRResponse{
		QRCode:    base64.StdEncoding.EncodeToString(qrCode),
		QRUrl:     fmt.Sprintf("https://qrapi.dev/qr/%s", qrID),
		Analytics: fmt.Sprintf("https://qrapi.dev/analytics/%s", qrID),
	}
	
	c.JSON(200, response)
}

func (app *App) generateQR(req QRRequest, plan string) ([]byte, error) {
	// Basic QR generation
	qr, err := qrcode.New(req.Data, qrcode.Medium)
	if err != nil {
		return nil, err
	}
	
	// Premium features
	if plan != "free" {
		// Custom colors (Pro+ only)
		if plan == "pro" || plan == "business" {
			qr.ForegroundColor = parseColor(req.Color)
			qr.BackgroundColor = parseColor(req.BgColor)
		}
	}
	
	return qr.PNG(req.Size)
}

func parseColor(hexColor string) color.Color {
	// Simple hex color parser
	if len(hexColor) != 7 || hexColor[0] != '#' {
		return color.Black
	}
	
	r, _ := strconv.ParseUint(hexColor[1:3], 16, 8)
	g, _ := strconv.ParseUint(hexColor[3:5], 16, 8)
	b, _ := strconv.ParseUint(hexColor[5:7], 16, 8)
	
	return color.RGBA{uint8(r), uint8(g), uint8(b), 255}
}

func (app *App) handleUsage(c *gin.Context) {
	user := c.MustGet("user").(*User)
	
	usage, err := app.getMonthlyUsage(user.ID)
	if err != nil {
		c.JSON(500, gin.H{"error": "Failed to get usage"})
		return
	}
	
	limit := plans[user.Plan]
	
	c.JSON(200, gin.H{
		"plan": user.Plan,
		"usage": usage,
		"limit": limit,
		"remaining": limit - usage,
		"reset_date": getNextMonthFirst(),
	})
}

func (app *App) handleQRView(c *gin.Context) {
	qrID := c.Param("id")
	
	// Increment scan count
	_, err := app.db.Exec("UPDATE qr_codes SET scans = scans + 1 WHERE id = ?", qrID)
	if err != nil {
		c.JSON(404, gin.H{"error": "QR code not found"})
		return
	}
	
	// Get QR data and redirect or show
	var data string
	err = app.db.QueryRow("SELECT data FROM qr_codes WHERE id = ?", qrID).Scan(&data)
	if err != nil {
		c.JSON(404, gin.H{"error": "QR code not found"})
		return
	}
	
	// If it's a URL, redirect. Otherwise, show the data
	if strings.HasPrefix(data, "http") {
		c.Redirect(302, data)
	} else {
		c.JSON(200, gin.H{"data": data})
	}
}

func (app *App) handleAnalytics(c *gin.Context) {
	qrID := c.Param("id")
	
	var scans int
	var createdAt time.Time
	err := app.db.QueryRow(
		"SELECT scans, created_at FROM qr_codes WHERE id = ?", qrID,
	).Scan(&scans, &createdAt)
	
	if err != nil {
		c.JSON(404, gin.H{"error": "QR code not found"})
		return
	}
	
	c.JSON(200, gin.H{
		"qr_id": qrID,
		"total_scans": scans,
		"created_at": createdAt,
		"avg_scans_per_day": float64(scans) / time.Since(createdAt).Hours() * 24,
	})
}

func (app *App) handleStripeWebhook(c *gin.Context) {
	// Handle Stripe webhooks for plan upgrades
	c.JSON(200, gin.H{"received": true})
}

// Helper functions
func generateAPIKey() string {
	bytes := make([]byte, 32)
	rand.Read(bytes)
	return "qr_" + hex.EncodeToString(bytes)
}

func generateID() string {
	bytes := make([]byte, 8)
	rand.Read(bytes)
	return hex.EncodeToString(bytes)
}

func (app *App) getUserByAPIKey(apiKey string) (*User, error) {
	user := &User{}
	err := app.db.QueryRow(
		"SELECT id, api_key, plan FROM users WHERE api_key = ?", apiKey,
	).Scan(&user.ID, &user.APIKey, &user.Plan)
	return user, err
}

func (app *App) getMonthlyUsage(userID int) (int, error) {
	key := fmt.Sprintf("usage:%d:%s", userID, time.Now().Format("2006-01"))
	val, err := app.redis.Get(context.Background(), key).Result()
	if err == redis.Nil {
		return 0, nil
	}
	if err != nil {
		return 0, err
	}
	return strconv.Atoi(val)
}

func (app *App) incrementUsage(userID int) {
	key := fmt.Sprintf("usage:%d:%s", userID, time.Now().Format("2006-01"))
	app.redis.Incr(context.Background(), key)
	app.redis.Expire(context.Background(), key, 32*24*time.Hour) // Expire next month
}

func (app *App) getLimiter(apiKey string) *rate.Limiter {
	if limiter, exists := app.limiter[apiKey]; exists {
		return limiter
	}
	
	// 10 requests per minute for free users
	limiter := rate.NewLimiter(rate.Every(6*time.Second), 10)
	app.limiter[apiKey] = limiter
	return limiter
}

func getNextMonthFirst() time.Time {
	now := time.Now()
	return time.Date(now.Year(), now.Month()+1, 1, 0, 0, 0, 0, now.Location())
}