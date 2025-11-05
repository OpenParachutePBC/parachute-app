package handlers

import (
	_ "embed"

	"github.com/gofiber/fiber/v3"
)

//go:embed openapi.yaml
var openapiSpec []byte

// SwaggerHandler serves OpenAPI documentation
type SwaggerHandler struct{}

// NewSwaggerHandler creates a new swagger handler
func NewSwaggerHandler() *SwaggerHandler {
	return &SwaggerHandler{}
}

// ServeSpec handles GET /api/docs/openapi.yaml
func (h *SwaggerHandler) ServeSpec(c fiber.Ctx) error {
	c.Set("Content-Type", "application/yaml")
	return c.Send(openapiSpec)
}

// ServeUI handles GET /api/docs
func (h *SwaggerHandler) ServeUI(c fiber.Ctx) error {
	html := `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Parachute API Documentation</title>
    <link rel="stylesheet" type="text/css" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.10.0/swagger-ui.css">
    <style>
        body {
            margin: 0;
            padding: 0;
        }
    </style>
</head>
<body>
    <div id="swagger-ui"></div>
    <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.10.0/swagger-ui-bundle.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5.10.0/swagger-ui-standalone-preset.js"></script>
    <script>
        window.onload = function() {
            const ui = SwaggerUIBundle({
                url: "/api/docs/openapi.yaml",
                dom_id: '#swagger-ui',
                deepLinking: true,
                presets: [
                    SwaggerUIBundle.presets.apis,
                    SwaggerUIStandalonePreset
                ],
                plugins: [
                    SwaggerUIBundle.plugins.DownloadUrl
                ],
                layout: "StandaloneLayout"
            });
            window.ui = ui;
        };
    </script>
</body>
</html>`

	c.Set("Content-Type", "text/html; charset=utf-8")
	return c.SendString(html)
}
