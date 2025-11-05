package main

import (
	"context"
	"log/slog"
	"os"

	"github.com/gofiber/fiber/v3"
	"github.com/gofiber/fiber/v3/middleware/cors"
	"github.com/unforced/parachute-backend/internal/acp"
	"github.com/unforced/parachute-backend/internal/api/handlers"
	"github.com/unforced/parachute-backend/internal/domain/conversation"
	"github.com/unforced/parachute-backend/internal/domain/file"
	"github.com/unforced/parachute-backend/internal/domain/registry"
	"github.com/unforced/parachute-backend/internal/domain/space"
	"github.com/unforced/parachute-backend/internal/storage/sqlite"
)

func main() {
	// Initialize structured logging
	logLevel := os.Getenv("LOG_LEVEL")
	var level slog.Level
	switch logLevel {
	case "debug", "DEBUG":
		level = slog.LevelDebug
	case "warn", "WARN", "warning", "WARNING":
		level = slog.LevelWarn
	case "error", "ERROR":
		level = slog.LevelError
	default:
		level = slog.LevelInfo
	}

	handler := slog.NewTextHandler(os.Stdout, &slog.HandlerOptions{
		Level: level,
	})
	logger := slog.New(handler)
	slog.SetDefault(logger)

	// Get configuration from environment
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	dbPath := os.Getenv("DATABASE_PATH")
	if dbPath == "" {
		dbPath = "./data/parachute.db"
	}

	parachuteRoot := os.Getenv("PARACHUTE_ROOT")
	if parachuteRoot == "" {
		// Default to ~/Parachute
		homeDir, err := os.UserHomeDir()
		if err != nil {
			slog.Error("Failed to get home directory", "error", err)
			os.Exit(1)
		}
		parachuteRoot = homeDir + "/Parachute"
	}

	apiKey := os.Getenv("ANTHROPIC_API_KEY")

	// Initialize database
	slog.Info("Connecting to database", "path", dbPath)
	db, err := sqlite.NewDatabase(dbPath)
	if err != nil {
		slog.Error("Failed to initialize database", "error", err)
		os.Exit(1)
	}
	defer db.Close()
	slog.Info("Database connected and migrations applied")

	// Initialize ACP client
	// If ANTHROPIC_API_KEY is not set, the SDK will use OAuth credentials from macOS keychain
	slog.Info("Initializing ACP client")
	if apiKey == "" {
		slog.Info("No ANTHROPIC_API_KEY provided, using Claude OAuth credentials from system keychain")
	}

	acpClient, err := acp.NewACPClient(apiKey)
	if err != nil {
		slog.Warn("Failed to initialize ACP client", "error", err)
		slog.Warn("Continuing without ACP integration")
		acpClient = nil
	} else if acpClient != nil {
		defer acpClient.Close()

		// Initialize ACP connection
		result, err := acpClient.Initialize()
		if err != nil {
			slog.Warn("Failed to initialize ACP", "error", err)
			slog.Warn("Continuing without ACP integration")
			acpClient.Close()
			acpClient = nil
		} else {
			slog.Info("Connected to ACP", "server", result.ServerName, "version", result.ServerVersion)
		}
	}

	// Initialize repositories
	spaceRepo := sqlite.NewSpaceRepository(db.DB)
	conversationRepo := sqlite.NewConversationRepository(db.DB)
	registryRepo := sqlite.NewRegistryRepository(db.DB)

	// Initialize services
	registryService := registry.NewService(registryRepo, parachuteRoot)
	spaceService := space.NewService(spaceRepo, parachuteRoot)
	conversationService := conversation.NewService(conversationRepo)
	spaceDBService := space.NewSpaceDatabaseService(parachuteRoot)

	// Log registry initialization
	slog.Info("Registry service initialized",
		"notes_folder", registryService.GetNotesFolder(context.Background()),
		"spaces_folder", registryService.GetSpacesFolder(context.Background()))

	// Run migration for existing spaces
	slog.Info("Running space.sqlite migration for existing spaces")
	if err := spaceDBService.MigrateAllSpaces(spaceRepo); err != nil {
		slog.Warn("Failed to migrate spaces", "error", err)
	}

	// Initialize context service for CLAUDE.md variable resolution
	contextService := space.NewContextService(spaceDBService)

	// Initialize file service
	slog.Info("Initializing file service", "root", parachuteRoot)
	fileService, err := file.NewService(parachuteRoot)
	if err != nil {
		slog.Error("Failed to initialize file service", "error", err)
		os.Exit(1)
	}
	slog.Info("File service initialized", "captures", parachuteRoot+"/captures", "spaces", parachuteRoot+"/spaces")

	// Initialize handlers
	registryHandler := handlers.NewRegistryHandler(registryService)
	spaceHandler := handlers.NewSpaceHandler(spaceService)
	fileHandler := handlers.NewFileHandler(fileService)
	spaceNotesHandler := handlers.NewSpaceNotesHandler(spaceService, spaceDBService)
	swaggerHandler := handlers.NewSwaggerHandler()

	// Initialize WebSocket handler if ACP is available
	var wsHandler *handlers.WebSocketHandler
	if acpClient != nil {
		wsHandler = handlers.NewWebSocketHandler(acpClient)
	}

	// Message handler works with or without ACP (acpClient can be nil)
	// Pass wsHandler for real-time streaming (can also be nil)
	messageHandler := handlers.NewMessageHandler(conversationService, spaceService, contextService, acpClient, wsHandler)

	// Create Fiber app
	app := fiber.New(fiber.Config{
		AppName: "Parachute Backend v1.0",
	})

	// Middleware
	app.Use(cors.New(cors.Config{
		AllowOrigins: []string{"*"},
		AllowHeaders: []string{"Origin", "Content-Type", "Accept"},
	}))

	app.Use(func(c fiber.Ctx) error {
		slog.Debug("HTTP request", "method", c.Method(), "path", c.Path())
		return c.Next()
	})

	// Health check endpoint
	app.Get("/health", func(c fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"status":      "ok",
			"service":     "parachute-backend",
			"version":     "0.1.0",
			"acp_enabled": acpClient != nil,
		})
	})

	// WebSocket endpoint
	if wsHandler != nil {
		app.Get("/ws", wsHandler.HandleUpgrade())
		slog.Info("WebSocket endpoint enabled", "url", "ws://localhost:"+port+"/ws")
	}

	// API routes
	api := app.Group("/api")

	// API documentation routes
	api.Get("/docs", swaggerHandler.ServeUI)
	api.Get("/docs/openapi.yaml", swaggerHandler.ServeSpec)

	// Registry routes (new flexible architecture)
	registry := api.Group("/registry")

	// Space operations
	registry.Get("/spaces", registryHandler.ListSpaces)
	registry.Post("/spaces/add", registryHandler.AddSpace)
	registry.Post("/spaces/create", registryHandler.CreateSpace)
	registry.Get("/spaces/:id", registryHandler.GetSpace)
	registry.Delete("/spaces/:id", registryHandler.RemoveSpace)

	// Capture operations
	registry.Get("/captures", registryHandler.ListCaptures)
	registry.Post("/captures", registryHandler.AddCapture)
	registry.Get("/captures/:id", registryHandler.GetCapture)

	// Settings operations
	registry.Get("/settings", registryHandler.GetSettings)
	registry.Put("/settings/:key", registryHandler.SetSetting)

	// Space routes (legacy, still used by frontend)
	spaces := api.Group("/spaces")
	spaces.Get("/", spaceHandler.List)
	spaces.Post("/", spaceHandler.Create)
	spaces.Get("/:id", spaceHandler.Get)
	spaces.Put("/:id", spaceHandler.Update)
	spaces.Delete("/:id", spaceHandler.Delete)

	// Space notes routes
	spaces.Get("/:id/notes", spaceNotesHandler.GetNotes)
	spaces.Post("/:id/notes", spaceNotesHandler.LinkNote)
	spaces.Put("/:id/notes/:capture_id", spaceNotesHandler.UpdateNoteContext)
	spaces.Delete("/:id/notes/:capture_id", spaceNotesHandler.UnlinkNote)
	spaces.Get("/:id/notes/:capture_id/content", spaceNotesHandler.GetNoteContent)
	spaces.Get("/:id/database/stats", spaceNotesHandler.GetDatabaseStats)
	spaces.Get("/:id/database/tables/:table_name", spaceNotesHandler.GetTableData)

	// Conversation routes
	conversations := api.Group("/conversations")
	conversations.Get("/", func(c fiber.Ctx) error {
		spaceID := c.Query("space_id")
		if spaceID == "" {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": "space_id query parameter required",
			})
		}

		convs, err := conversationService.ListConversations(c.Context(), spaceID)
		if err != nil {
			slog.Error("Failed to list conversations", "error", err, "space_id", spaceID)
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": "Failed to list conversations",
			})
		}

		// Ensure we always return an array, never null
		if convs == nil {
			convs = []*conversation.Conversation{}
		}

		return c.JSON(fiber.Map{
			"conversations": convs,
		})
	})

	conversations.Post("/", func(c fiber.Ctx) error {
		var params conversation.CreateConversationParams
		if err := c.Bind().JSON(&params); err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": "Invalid request body",
			})
		}

		conv, err := conversationService.CreateConversation(c.Context(), params)
		if err != nil {
			slog.Error("Failed to create conversation", "error", err, "params", params)
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": err.Error(),
			})
		}

		return c.Status(fiber.StatusCreated).JSON(conv)
	})

	conversations.Put("/:id", func(c fiber.Ctx) error {
		id := c.Params("id")
		if id == "" {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": "conversation ID is required",
			})
		}

		var body struct {
			Title string `json:"title"`
		}
		if err := c.Bind().JSON(&body); err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": "Invalid request body",
			})
		}

		if body.Title == "" {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": "title is required",
			})
		}

		conv, err := conversationService.UpdateConversation(c.Context(), id, body.Title)
		if err != nil {
			slog.Error("Failed to update conversation", "error", err, "id", id)
			return c.Status(fiber.StatusInternalServerError).JSON(fiber.Map{
				"error": err.Error(),
			})
		}

		return c.JSON(conv)
	})

	// Message routes
	messages := api.Group("/messages")
	messages.Get("/", messageHandler.ListMessages)
	messages.Post("/", messageHandler.SendMessage)

	// File/Capture routes
	captures := api.Group("/captures")
	captures.Post("/upload", fileHandler.UploadCapture)
	captures.Get("/", fileHandler.ListCaptures)
	captures.Get("/:filename", fileHandler.DownloadCapture)
	captures.Post("/:filename/transcript", fileHandler.UploadTranscript)
	captures.Get("/:filename/transcript", fileHandler.DownloadTranscript)
	captures.Delete("/:filename", fileHandler.DeleteCapture)

	// File browser routes
	files := api.Group("/files")
	files.Get("/browse", fileHandler.BrowseFiles)
	files.Get("/read", fileHandler.ReadFile)
	files.Get("/download", fileHandler.DownloadFile)

	// Start server
	slog.Info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	slog.Info("Parachute Backend v1.0 starting", "port", port)
	slog.Info("Endpoints configured",
		"health", "http://localhost:"+port+"/health",
		"api", "http://localhost:"+port+"/api/*",
		"websocket", wsHandler != nil)
	slog.Info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

	if err := app.Listen(":" + port); err != nil {
		slog.Error("Server failed to start", "error", err)
		os.Exit(1)
	}
}
