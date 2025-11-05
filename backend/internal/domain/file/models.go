package file

import (
	"time"
)

// CaptureMetadata represents metadata for a voice recording
type CaptureMetadata struct {
	ID             string    `json:"id"`
	Filename       string    `json:"filename"`
	Timestamp      time.Time `json:"timestamp"`
	Duration       float64   `json:"duration"` // seconds
	Source         string    `json:"source"`   // phone, omi, desktop
	DeviceID       string    `json:"deviceId,omitempty"`
	Size           int64     `json:"size"`
	HasTranscript  bool      `json:"hasTranscript"`
	TranscriptMode string    `json:"transcriptMode,omitempty"` // api, local
	ModelUsed      string    `json:"modelUsed,omitempty"`
	Tags           []string  `json:"tags,omitempty"`
	CreatedAt      time.Time `json:"createdAt"`
	UpdatedAt      time.Time `json:"updatedAt"`
}

// CaptureInfo represents a summary of a capture for listing
type CaptureInfo struct {
	ID            string    `json:"id"`
	Filename      string    `json:"filename"`
	Title         string    `json:"title,omitempty"`
	Timestamp     time.Time `json:"timestamp"`
	Duration      float64   `json:"duration"`
	Source        string    `json:"source"`
	DeviceID      string    `json:"deviceId,omitempty"`
	Size          int64     `json:"size"`
	HasTranscript bool      `json:"hasTranscript"`
	Transcript    string    `json:"transcript,omitempty"`
	AudioURL      string    `json:"audioUrl"`
	TranscriptURL string    `json:"transcriptUrl,omitempty"`
}

// TranscriptData represents transcript content and metadata
type TranscriptData struct {
	Transcript        string `json:"transcript"`
	Title             string `json:"title,omitempty"`
	TranscriptionMode string `json:"transcriptionMode"` // api, local
	ModelUsed         string `json:"modelUsed,omitempty"`
}

// UploadCaptureParams represents parameters for uploading a capture
type UploadCaptureParams struct {
	Timestamp time.Time
	Duration  float64
	Source    string
	DeviceID  string
}

// FileInfo represents information about a file or directory
type FileInfo struct {
	Name        string    `json:"name"`
	Path        string    `json:"path"` // Relative to Parachute root
	IsDirectory bool      `json:"isDirectory"`
	Size        int64     `json:"size"`
	ModifiedAt  time.Time `json:"modifiedAt"`
	Extension   string    `json:"extension,omitempty"`
	IsMarkdown  bool      `json:"isMarkdown"`
	IsAudio     bool      `json:"isAudio"`
	DownloadURL string    `json:"downloadUrl,omitempty"`
}

// BrowseResult represents the result of browsing a directory
type BrowseResult struct {
	Path        string     `json:"path"`   // Current path relative to root
	Parent      string     `json:"parent"` // Parent path, empty if at root
	Files       []FileInfo `json:"files"`
	Directories []FileInfo `json:"directories"`
}
