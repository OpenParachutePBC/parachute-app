package file

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
)

// Service provides file management for the Parachute folder structure
type Service struct {
	rootPath string
}

// NewService creates a new file service
func NewService(rootPath string) (*Service, error) {
	// Ensure root path exists
	if err := ensureDir(rootPath); err != nil {
		return nil, fmt.Errorf("failed to create root directory: %w", err)
	}

	// Ensure captures and spaces directories exist
	capturesPath := filepath.Join(rootPath, "captures")
	if err := ensureDir(capturesPath); err != nil {
		return nil, fmt.Errorf("failed to create captures directory: %w", err)
	}

	spacesPath := filepath.Join(rootPath, "spaces")
	if err := ensureDir(spacesPath); err != nil {
		return nil, fmt.Errorf("failed to create spaces directory: %w", err)
	}

	return &Service{
		rootPath: rootPath,
	}, nil
}

// SaveCapture saves an audio capture to the captures folder
func (s *Service) SaveCapture(audioData io.Reader, params UploadCaptureParams) (*CaptureMetadata, error) {
	// Generate filename from timestamp
	filename := formatTimestampForFilename(params.Timestamp) + ".wav"
	audioPath := filepath.Join(s.rootPath, "captures", filename)

	// Save audio file
	audioFile, err := os.Create(audioPath)
	if err != nil {
		return nil, fmt.Errorf("failed to create audio file: %w", err)
	}
	defer audioFile.Close()

	written, err := io.Copy(audioFile, audioData)
	if err != nil {
		return nil, fmt.Errorf("failed to write audio file: %w", err)
	}

	// Create metadata
	now := time.Now()
	metadata := &CaptureMetadata{
		ID:            uuid.New().String(),
		Filename:      filename,
		Timestamp:     params.Timestamp,
		Duration:      params.Duration,
		Source:        params.Source,
		DeviceID:      params.DeviceID,
		Size:          written,
		HasTranscript: false,
		CreatedAt:     now,
		UpdatedAt:     now,
	}

	// Save metadata JSON
	if err := s.saveMetadataJSON(filename, metadata); err != nil {
		return nil, fmt.Errorf("failed to save metadata: %w", err)
	}

	return metadata, nil
}

// SaveTranscript saves a transcript for an existing capture
func (s *Service) SaveTranscript(filename string, data TranscriptData) error {
	// Verify audio file exists
	audioPath := filepath.Join(s.rootPath, "captures", filename)
	if _, err := os.Stat(audioPath); os.IsNotExist(err) {
		return fmt.Errorf("audio file not found: %s", filename)
	}

	// Load existing metadata
	metadata, err := s.loadMetadataJSON(filename)
	if err != nil {
		// If no metadata exists, create minimal metadata
		metadata = &CaptureMetadata{
			Filename:  filename,
			Timestamp: parseTimestampFromFilename(filename),
		}
	}

	// Update metadata
	metadata.HasTranscript = true
	metadata.TranscriptMode = data.TranscriptionMode
	metadata.ModelUsed = data.ModelUsed
	metadata.UpdatedAt = time.Now()

	// Generate markdown filename
	mdFilename := strings.TrimSuffix(filename, ".wav") + ".md"
	mdPath := filepath.Join(s.rootPath, "captures", mdFilename)

	// Generate markdown content
	markdown := s.generateTranscriptMarkdown(metadata, data.Transcript, data.Title)

	// Save markdown file
	if err := os.WriteFile(mdPath, []byte(markdown), 0644); err != nil {
		return fmt.Errorf("failed to write transcript: %w", err)
	}

	// Update metadata JSON
	if err := s.saveMetadataJSON(filename, metadata); err != nil {
		return fmt.Errorf("failed to update metadata: %w", err)
	}

	return nil
}

// ListCaptures returns a list of all captures
func (s *Service) ListCaptures(limit, offset int) ([]CaptureInfo, int, error) {
	capturesDir := filepath.Join(s.rootPath, "captures")

	entries, err := os.ReadDir(capturesDir)
	if err != nil {
		return nil, 0, fmt.Errorf("failed to read captures directory: %w", err)
	}

	// Collect all captures
	var captures []CaptureInfo
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".wav") {
			continue
		}

		// Load metadata
		metadata, err := s.loadMetadataJSON(entry.Name())
		if err != nil {
			// If no metadata, create minimal info from file
			info, err := entry.Info()
			if err != nil {
				continue
			}

			metadata = &CaptureMetadata{
				Filename:      entry.Name(),
				Timestamp:     parseTimestampFromFilename(entry.Name()),
				Size:          info.Size(),
				HasTranscript: s.transcriptExists(entry.Name()),
			}
		}

		captureInfo := CaptureInfo{
			ID:            metadata.ID,
			Filename:      metadata.Filename,
			Timestamp:     metadata.Timestamp,
			Duration:      metadata.Duration,
			Source:        metadata.Source,
			DeviceID:      metadata.DeviceID,
			Size:          metadata.Size,
			HasTranscript: metadata.HasTranscript,
			AudioURL:      "/api/captures/" + metadata.Filename,
		}

		if metadata.HasTranscript {
			mdFilename := strings.TrimSuffix(metadata.Filename, ".wav") + ".md"
			captureInfo.TranscriptURL = "/api/captures/" + mdFilename

			// Extract title and transcript from markdown
			if title := s.extractTitleFromMarkdown(entry.Name()); title != "" {
				captureInfo.Title = title
			}

			// Extract transcript content from markdown
			if transcript := s.extractTranscriptFromMarkdown(entry.Name()); transcript != "" {
				captureInfo.Transcript = transcript
			}
		}

		captures = append(captures, captureInfo)
	}

	// Sort by timestamp descending (newest first)
	sort.Slice(captures, func(i, j int) bool {
		return captures[i].Timestamp.After(captures[j].Timestamp)
	})

	total := len(captures)

	// Apply pagination
	if offset >= len(captures) {
		return []CaptureInfo{}, total, nil
	}

	end := offset + limit
	if end > len(captures) {
		end = len(captures)
	}

	return captures[offset:end], total, nil
}

// GetCapture returns a reader for the audio file
func (s *Service) GetCapture(filename string) (io.ReadCloser, error) {
	audioPath := filepath.Join(s.rootPath, "captures", filename)

	file, err := os.Open(audioPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("capture not found: %s", filename)
		}
		return nil, fmt.Errorf("failed to open capture: %w", err)
	}

	return file, nil
}

// GetTranscript returns the transcript markdown content
func (s *Service) GetTranscript(filename string) (string, error) {
	mdFilename := strings.TrimSuffix(filename, ".wav") + ".md"
	mdPath := filepath.Join(s.rootPath, "captures", mdFilename)

	content, err := os.ReadFile(mdPath)
	if err != nil {
		if os.IsNotExist(err) {
			return "", fmt.Errorf("transcript not found for: %s", filename)
		}
		return "", fmt.Errorf("failed to read transcript: %w", err)
	}

	return string(content), nil
}

// DeleteCapture deletes a capture and all associated files
func (s *Service) DeleteCapture(filename string) error {
	capturesDir := filepath.Join(s.rootPath, "captures")

	// Delete audio file
	audioPath := filepath.Join(capturesDir, filename)
	if err := os.Remove(audioPath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed to delete audio file: %w", err)
	}

	// Delete transcript if exists
	mdFilename := strings.TrimSuffix(filename, ".wav") + ".md"
	mdPath := filepath.Join(capturesDir, mdFilename)
	os.Remove(mdPath) // Ignore error if doesn't exist

	// Delete metadata JSON if exists
	jsonFilename := strings.TrimSuffix(filename, ".wav") + ".json"
	jsonPath := filepath.Join(capturesDir, jsonFilename)
	os.Remove(jsonPath) // Ignore error if doesn't exist

	return nil
}

// Helper functions

func (s *Service) saveMetadataJSON(filename string, metadata *CaptureMetadata) error {
	jsonFilename := strings.TrimSuffix(filename, ".wav") + ".json"
	jsonPath := filepath.Join(s.rootPath, "captures", jsonFilename)

	data, err := json.MarshalIndent(metadata, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(jsonPath, data, 0644)
}

func (s *Service) loadMetadataJSON(filename string) (*CaptureMetadata, error) {
	jsonFilename := strings.TrimSuffix(filename, ".wav") + ".json"
	jsonPath := filepath.Join(s.rootPath, "captures", jsonFilename)

	data, err := os.ReadFile(jsonPath)
	if err != nil {
		return nil, err
	}

	var metadata CaptureMetadata
	if err := json.Unmarshal(data, &metadata); err != nil {
		return nil, err
	}

	return &metadata, nil
}

func (s *Service) transcriptExists(filename string) bool {
	mdFilename := strings.TrimSuffix(filename, ".wav") + ".md"
	mdPath := filepath.Join(s.rootPath, "captures", mdFilename)
	_, err := os.Stat(mdPath)
	return err == nil
}

func (s *Service) generateTranscriptMarkdown(metadata *CaptureMetadata, transcript string, customTitle string) string {
	var sb strings.Builder

	// Frontmatter
	sb.WriteString("---\n")
	sb.WriteString(fmt.Sprintf("id: %s\n", metadata.ID))
	sb.WriteString(fmt.Sprintf("filename: %s\n", metadata.Filename))

	// Add title to frontmatter if provided
	if customTitle != "" {
		sb.WriteString(fmt.Sprintf("title: %s\n", customTitle))
	}

	sb.WriteString(fmt.Sprintf("timestamp: %s\n", metadata.Timestamp.Format(time.RFC3339)))
	sb.WriteString(fmt.Sprintf("duration: %.2f\n", metadata.Duration))
	sb.WriteString(fmt.Sprintf("source: %s\n", metadata.Source))

	if metadata.DeviceID != "" {
		sb.WriteString(fmt.Sprintf("deviceId: %s\n", metadata.DeviceID))
	}

	if metadata.TranscriptMode != "" {
		sb.WriteString(fmt.Sprintf("transcriptionMode: %s\n", metadata.TranscriptMode))
	}

	if metadata.ModelUsed != "" {
		sb.WriteString(fmt.Sprintf("modelUsed: %s\n", metadata.ModelUsed))
	}

	sb.WriteString("---\n\n")

	// Title - use custom title if provided, otherwise generate from timestamp
	var title string
	if customTitle != "" {
		title = customTitle
	} else {
		title = fmt.Sprintf("Recording - %s", metadata.Timestamp.Format("January 2, 2006 3:04 PM"))
	}
	sb.WriteString(fmt.Sprintf("# %s\n\n", title))

	// Metadata section
	sb.WriteString(fmt.Sprintf("**Duration:** %.1fs  \n", metadata.Duration))
	sb.WriteString(fmt.Sprintf("**Source:** %s  \n", metadata.Source))
	if metadata.TranscriptMode != "" {
		sb.WriteString(fmt.Sprintf("**Transcribed:** %s\n\n", metadata.TranscriptMode))
	}

	sb.WriteString("---\n\n")

	// Transcript content
	sb.WriteString(transcript)
	sb.WriteString("\n")

	return sb.String()
}

// formatTimestampForFilename converts a timestamp to filesystem-safe format
// Format: 2025-10-25_14-30-22
func formatTimestampForFilename(t time.Time) string {
	return fmt.Sprintf("%04d-%02d-%02d_%02d-%02d-%02d",
		t.Year(), t.Month(), t.Day(),
		t.Hour(), t.Minute(), t.Second())
}

// parseTimestampFromFilename attempts to parse timestamp from filename
func parseTimestampFromFilename(filename string) time.Time {
	// Extract: 2025-10-25_14-30-22 from filename
	parts := strings.Split(filename, "_")
	if len(parts) < 2 {
		return time.Now()
	}

	dateStr := parts[0]
	timeStr := strings.TrimSuffix(parts[1], ".wav")

	// Parse date
	dateParts := strings.Split(dateStr, "-")
	if len(dateParts) != 3 {
		return time.Now()
	}

	// Parse time
	timeParts := strings.Split(timeStr, "-")
	if len(timeParts) != 3 {
		return time.Now()
	}

	// Convert to time.Time
	layout := "2006-01-02_15-04-05"
	fullStr := fmt.Sprintf("%s_%s", dateStr, timeStr)
	t, err := time.Parse(layout, fullStr)
	if err != nil {
		return time.Now()
	}

	return t
}

// Browse lists files and directories at the given path relative to Parachute root
func (s *Service) Browse(relativePath string) (*BrowseResult, error) {
	// Security: prevent path traversal attacks
	cleanPath := filepath.Clean(relativePath)
	if strings.Contains(cleanPath, "..") {
		return nil, fmt.Errorf("invalid path: path traversal not allowed")
	}

	// Build absolute path
	var absPath string
	if cleanPath == "." || cleanPath == "" || cleanPath == "/" {
		absPath = s.rootPath
		cleanPath = ""
	} else {
		absPath = filepath.Join(s.rootPath, cleanPath)
	}

	// Verify path exists and is within root
	if !strings.HasPrefix(absPath, s.rootPath) {
		return nil, fmt.Errorf("invalid path: outside Parachute directory")
	}

	info, err := os.Stat(absPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, fmt.Errorf("path not found: %s", relativePath)
		}
		return nil, fmt.Errorf("failed to access path: %w", err)
	}

	if !info.IsDir() {
		return nil, fmt.Errorf("path is not a directory: %s", relativePath)
	}

	// Read directory contents
	entries, err := os.ReadDir(absPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read directory: %w", err)
	}

	// Separate files and directories
	var files []FileInfo
	var directories []FileInfo

	for _, entry := range entries {
		// Skip hidden files and metadata files
		if strings.HasPrefix(entry.Name(), ".") || strings.HasSuffix(entry.Name(), ".json") {
			continue
		}

		info, err := entry.Info()
		if err != nil {
			continue
		}

		itemPath := filepath.Join(cleanPath, entry.Name())
		ext := filepath.Ext(entry.Name())
		isMarkdown := ext == ".md"
		isAudio := ext == ".wav" || ext == ".mp3" || ext == ".m4a"

		fileInfo := FileInfo{
			Name:        entry.Name(),
			Path:        itemPath,
			IsDirectory: entry.IsDir(),
			Size:        info.Size(),
			ModifiedAt:  info.ModTime(),
			Extension:   ext,
			IsMarkdown:  isMarkdown,
			IsAudio:     isAudio,
		}

		if !entry.IsDir() {
			fileInfo.DownloadURL = "/api/files/download?path=" + itemPath
		}

		if entry.IsDir() {
			directories = append(directories, fileInfo)
		} else {
			files = append(files, fileInfo)
		}
	}

	// Sort alphabetically
	sort.Slice(files, func(i, j int) bool {
		return files[i].Name < files[j].Name
	})
	sort.Slice(directories, func(i, j int) bool {
		return directories[i].Name < directories[j].Name
	})

	// Calculate parent path
	parent := ""
	if cleanPath != "" {
		parent = filepath.Dir(cleanPath)
		if parent == "." {
			parent = ""
		}
	}

	return &BrowseResult{
		Path:        cleanPath,
		Parent:      parent,
		Files:       files,
		Directories: directories,
	}, nil
}

// ReadFile reads the content of a file at the given path
func (s *Service) ReadFile(relativePath string) (string, error) {
	// Security: prevent path traversal
	cleanPath := filepath.Clean(relativePath)
	if strings.Contains(cleanPath, "..") {
		return "", fmt.Errorf("invalid path: path traversal not allowed")
	}

	// Build absolute path
	absPath := filepath.Join(s.rootPath, cleanPath)

	// Verify path is within root
	if !strings.HasPrefix(absPath, s.rootPath) {
		return "", fmt.Errorf("invalid path: outside Parachute directory")
	}

	// Read file
	content, err := os.ReadFile(absPath)
	if err != nil {
		if os.IsNotExist(err) {
			return "", fmt.Errorf("file not found: %s", relativePath)
		}
		return "", fmt.Errorf("failed to read file: %w", err)
	}

	return string(content), nil
}

// DownloadFile returns a reader for downloading a file
func (s *Service) DownloadFile(relativePath string) (io.ReadCloser, string, error) {
	// Security: prevent path traversal
	cleanPath := filepath.Clean(relativePath)
	if strings.Contains(cleanPath, "..") {
		return nil, "", fmt.Errorf("invalid path: path traversal not allowed")
	}

	// Build absolute path
	absPath := filepath.Join(s.rootPath, cleanPath)

	// Verify path is within root
	if !strings.HasPrefix(absPath, s.rootPath) {
		return nil, "", fmt.Errorf("invalid path: outside Parachute directory")
	}

	// Open file
	file, err := os.Open(absPath)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, "", fmt.Errorf("file not found: %s", relativePath)
		}
		return nil, "", fmt.Errorf("failed to open file: %w", err)
	}

	// Get filename for Content-Disposition header
	filename := filepath.Base(cleanPath)

	return file, filename, nil
}

// ensureDir ensures a directory exists, creating it if necessary
func ensureDir(path string) error {
	info, err := os.Stat(path)
	if err != nil {
		if os.IsNotExist(err) {
			return os.MkdirAll(path, 0755)
		}
		return err
	}

	if !info.IsDir() {
		return fmt.Errorf("path exists but is not a directory: %s", path)
	}

	return nil
}

// extractTitleFromMarkdown extracts the title field from markdown frontmatter
func (s *Service) extractTitleFromMarkdown(audioFilename string) string {
	mdFilename := strings.TrimSuffix(audioFilename, ".wav") + ".md"
	mdPath := filepath.Join(s.rootPath, "captures", mdFilename)

	content, err := os.ReadFile(mdPath)
	if err != nil {
		return ""
	}

	// Parse frontmatter (between --- markers)
	text := string(content)
	if !strings.HasPrefix(text, "---\n") {
		return ""
	}

	// Find the end of frontmatter
	endIndex := strings.Index(text[4:], "\n---\n")
	if endIndex == -1 {
		return ""
	}

	frontmatter := text[4 : endIndex+4]

	// Look for title: line
	lines := strings.Split(frontmatter, "\n")
	for _, line := range lines {
		if strings.HasPrefix(line, "title:") {
			title := strings.TrimSpace(strings.TrimPrefix(line, "title:"))
			return title
		}
	}

	return ""
}

// extractTranscriptFromMarkdown extracts the transcript content from markdown file
func (s *Service) extractTranscriptFromMarkdown(audioFilename string) string {
	mdFilename := strings.TrimSuffix(audioFilename, ".wav") + ".md"
	mdPath := filepath.Join(s.rootPath, "captures", mdFilename)

	content, err := os.ReadFile(mdPath)
	if err != nil {
		return ""
	}

	text := string(content)

	// Find the end of frontmatter (second --- marker)
	if !strings.HasPrefix(text, "---\n") {
		return text // No frontmatter, return entire content
	}

	endIndex := strings.Index(text[4:], "\n---\n")
	if endIndex == -1 {
		return "" // Malformed frontmatter
	}

	// Extract everything after the frontmatter
	transcriptStart := 4 + endIndex + 5 // Skip "---\n"
	if transcriptStart >= len(text) {
		return ""
	}

	transcript := strings.TrimSpace(text[transcriptStart:])

	// Skip the title heading (# Title) and metadata section
	lines := strings.Split(transcript, "\n")
	var contentLines []string
	skipHeading := false
	foundContentStart := false

	for _, line := range lines {
		// Skip first heading
		if !foundContentStart && strings.HasPrefix(line, "# ") {
			skipHeading = true
			continue
		}

		// Skip metadata lines after heading until we hit the separator
		if skipHeading {
			trimmed := strings.TrimSpace(line)
			if trimmed == "" {
				continue
			}
			if trimmed == "---" {
				skipHeading = false
				foundContentStart = true
				continue
			}
			// Skip metadata like **Duration:** etc
			if strings.HasPrefix(trimmed, "**") {
				continue
			}
		}

		if foundContentStart || !skipHeading {
			contentLines = append(contentLines, line)
		}
	}

	return strings.TrimSpace(strings.Join(contentLines, "\n"))
}
