package acp

import (
	"encoding/json"
	"testing"
)

func TestParsePermissionRequest(t *testing.T) {
	tests := []struct {
		name    string
		reqJSON string
		wantErr bool
	}{
		{
			name: "valid web search permission request",
			reqJSON: `{
				"jsonrpc": "2.0",
				"id": 1,
				"method": "session/request_permission",
				"params": {
					"sessionId": "test-session-123",
					"toolCall": {
						"toolCallId": "toolu_123",
						"rawInput": {
							"query": "weather today"
						}
					},
					"options": [
						{"optionId": "allow", "name": "Allow", "kind": "allow"},
						{"optionId": "reject", "name": "Reject", "kind": "reject"}
					]
				}
			}`,
			wantErr: false,
		},
		{
			name: "valid file read permission request",
			reqJSON: `{
				"jsonrpc": "2.0",
				"id": 2,
				"method": "session/request_permission",
				"params": {
					"sessionId": "test-session-456",
					"toolCall": {
						"toolCallId": "toolu_456",
						"rawInput": {
							"operation": "read",
							"path": "/tmp/test.txt"
						}
					},
					"options": [
						{"optionId": "allow_once", "name": "Allow Once", "kind": "allow"},
						{"optionId": "reject_once", "name": "Reject Once", "kind": "reject"}
					]
				}
			}`,
			wantErr: false,
		},
		{
			name: "wrong method",
			reqJSON: `{
				"jsonrpc": "2.0",
				"id": 3,
				"method": "session/other_method",
				"params": {}
			}`,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var req JSONRPCIncomingRequest
			if err := json.Unmarshal([]byte(tt.reqJSON), &req); err != nil {
				t.Fatalf("Failed to unmarshal test JSON: %v", err)
			}

			permReq, err := ParsePermissionRequest(&req)
			if (err != nil) != tt.wantErr {
				t.Errorf("ParsePermissionRequest() error = %v, wantErr %v", err, tt.wantErr)
				return
			}

			if !tt.wantErr && permReq == nil {
				t.Error("Expected valid PermissionRequest but got nil")
			}
		})
	}
}

func TestShouldAutoApprove(t *testing.T) {
	tests := []struct {
		name     string
		toolCall ToolCallInfo
		want     bool
	}{
		{
			name: "web search should auto-approve",
			toolCall: ToolCallInfo{
				ToolCallID: "toolu_123",
				RawInput: map[string]interface{}{
					"query": "weather today",
				},
			},
			want: true,
		},
		{
			name: "web fetch should auto-approve",
			toolCall: ToolCallInfo{
				ToolCallID: "toolu_124",
				RawInput: map[string]interface{}{
					"url":    "https://example.com",
					"prompt": "fetch this",
				},
			},
			want: true,
		},
		{
			name: "file read should auto-approve",
			toolCall: ToolCallInfo{
				ToolCallID: "toolu_125",
				RawInput: map[string]interface{}{
					"operation": "read",
					"path":      "/tmp/test.txt",
				},
			},
			want: true,
		},
		{
			name: "file glob should auto-approve",
			toolCall: ToolCallInfo{
				ToolCallID: "toolu_126",
				RawInput: map[string]interface{}{
					"operation": "glob",
					"pattern":   "*.go",
				},
			},
			want: true,
		},
		{
			name: "file grep should auto-approve",
			toolCall: ToolCallInfo{
				ToolCallID: "toolu_127",
				RawInput: map[string]interface{}{
					"operation": "grep",
					"pattern":   "TODO",
				},
			},
			want: true,
		},
		{
			name: "file list should auto-approve",
			toolCall: ToolCallInfo{
				ToolCallID: "toolu_128",
				RawInput: map[string]interface{}{
					"operation": "list",
					"path":      "/tmp",
				},
			},
			want: true,
		},
		{
			name: "safe bash command should auto-approve",
			toolCall: ToolCallInfo{
				ToolCallID: "toolu_129",
				RawInput: map[string]interface{}{
					"command": "ls -la",
				},
			},
			want: true,
		},
		{
			name: "git status should auto-approve",
			toolCall: ToolCallInfo{
				ToolCallID: "toolu_130",
				RawInput: map[string]interface{}{
					"command": "git status",
				},
			},
			want: true,
		},
		{
			name: "file write should NOT auto-approve",
			toolCall: ToolCallInfo{
				ToolCallID: "toolu_131",
				RawInput: map[string]interface{}{
					"operation": "write",
					"path":      "/tmp/test.txt",
					"content":   "data",
				},
			},
			want: false,
		},
		{
			name: "unsafe bash command should NOT auto-approve",
			toolCall: ToolCallInfo{
				ToolCallID: "toolu_132",
				RawInput: map[string]interface{}{
					"command": "rm -rf /",
				},
			},
			want: false,
		},
		{
			name: "unknown tool should NOT auto-approve",
			toolCall: ToolCallInfo{
				ToolCallID: "toolu_133",
				RawInput: map[string]interface{}{
					"unknown": "operation",
				},
			},
			want: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ShouldAutoApprove(tt.toolCall)
			if got != tt.want {
				t.Errorf("ShouldAutoApprove() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestFindAllowOption(t *testing.T) {
	tests := []struct {
		name    string
		options []PermissionOption
		want    string // optionId we expect to get, empty if nil expected
	}{
		{
			name: "prefer 'allow' over others",
			options: []PermissionOption{
				{OptionID: "reject", Name: "Reject", Kind: "reject"},
				{OptionID: "allow", Name: "Allow", Kind: "allow"},
				{OptionID: "allow_once", Name: "Allow Once", Kind: "allow"},
			},
			want: "allow",
		},
		{
			name: "use 'allow_once' if no 'allow'",
			options: []PermissionOption{
				{OptionID: "reject", Name: "Reject", Kind: "reject"},
				{OptionID: "allow_once", Name: "Allow Once", Kind: "allow"},
			},
			want: "allow_once",
		},
		{
			name: "use 'allow_always' if only option",
			options: []PermissionOption{
				{OptionID: "allow_always", Name: "Allow Always", Kind: "allow"},
				{OptionID: "reject", Name: "Reject", Kind: "reject"},
			},
			want: "allow_always",
		},
		{
			name: "return nil if no allow options",
			options: []PermissionOption{
				{OptionID: "reject", Name: "Reject", Kind: "reject"},
				{OptionID: "reject_once", Name: "Reject Once", Kind: "reject"},
			},
			want: "",
		},
		{
			name:    "return nil for empty options",
			options: []PermissionOption{},
			want:    "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := FindAllowOption(tt.options)
			if tt.want == "" {
				if got != nil {
					t.Errorf("FindAllowOption() = %v, want nil", got)
				}
			} else {
				if got == nil {
					t.Errorf("FindAllowOption() = nil, want %s", tt.want)
				} else if got.OptionID != tt.want {
					t.Errorf("FindAllowOption() = %s, want %s", got.OptionID, tt.want)
				}
			}
		})
	}
}

func TestPermissionResponseSerialization(t *testing.T) {
	resp := PermissionResponse{
		Outcome: PermissionOutcome{
			Outcome:  "selected",
			OptionID: "allow",
		},
	}

	data, err := json.Marshal(resp)
	if err != nil {
		t.Fatalf("Failed to marshal PermissionResponse: %v", err)
	}

	expected := `{"outcome":{"outcome":"selected","optionId":"allow"}}`
	if string(data) != expected {
		t.Errorf("Marshaled JSON = %s, want %s", string(data), expected)
	}

	// Test deserialization
	var decoded PermissionResponse
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("Failed to unmarshal PermissionResponse: %v", err)
	}

	if decoded.Outcome.OptionID != resp.Outcome.OptionID {
		t.Errorf("Decoded optionId = %s, want %s", decoded.Outcome.OptionID, resp.Outcome.OptionID)
	}
	if decoded.Outcome.Outcome != resp.Outcome.Outcome {
		t.Errorf("Decoded outcome = %s, want %s", decoded.Outcome.Outcome, resp.Outcome.Outcome)
	}
}
