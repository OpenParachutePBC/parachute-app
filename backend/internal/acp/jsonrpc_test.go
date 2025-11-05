package acp

import (
	"encoding/json"
	"testing"
)

func TestJSONRPCRequestWithZeroID(t *testing.T) {
	// Test that we can correctly parse requests with ID=0
	jsonStr := `{"jsonrpc":"2.0","id":0,"method":"session/request_permission","params":{"sessionId":"test"}}`

	var req JSONRPCIncomingRequest
	err := json.Unmarshal([]byte(jsonStr), &req)
	if err != nil {
		t.Fatalf("Failed to unmarshal: %v", err)
	}

	if req.ID == nil {
		t.Error("Expected ID to be present, got nil")
	} else if *req.ID != 0 {
		t.Errorf("Expected ID=0, got ID=%d", *req.ID)
	}

	if req.Method != "session/request_permission" {
		t.Errorf("Expected method=session/request_permission, got %s", req.Method)
	}

	// Test the condition used in readLoop
	if !(req.ID != nil && req.Method != "") {
		t.Error("Condition (req.ID != nil && req.Method != '') should be true for ID=0")
	}
}

func TestJSONRPCNotificationParsing(t *testing.T) {
	// Test that notifications (no ID) are NOT parsed as requests
	jsonStr := `{"jsonrpc":"2.0","method":"session/update","params":{"sessionUpdate":"tool_call"}}`

	var req JSONRPCIncomingRequest
	err := json.Unmarshal([]byte(jsonStr), &req)
	if err != nil {
		t.Fatalf("Failed to unmarshal: %v", err)
	}

	if req.ID != nil {
		t.Errorf("Expected ID to be nil for notification, got %v", *req.ID)
	}

	if req.Method != "session/update" {
		t.Errorf("Expected method=session/update, got %s", req.Method)
	}

	// Test the condition used in readLoop - should be FALSE for notifications
	if req.ID != nil && req.Method != "" {
		t.Error("Notification should NOT pass the request condition (ID should be nil)")
	}
}

func TestJSONRPCResponseWithZeroID(t *testing.T) {
	// Test that we correctly handle responses with ID=0
	jsonStr := `{"jsonrpc":"2.0","id":0,"result":{"optionId":"allow"}}`

	var resp JSONRPCResponse
	err := json.Unmarshal([]byte(jsonStr), &resp)
	if err != nil {
		t.Fatalf("Failed to unmarshal: %v", err)
	}

	if resp.ID != 0 {
		t.Errorf("Expected ID=0, got ID=%d", resp.ID)
	}

	// This is the bug! The condition resp.ID != 0 will be TRUE when ID=0
	// So it will be parsed as a response
	if resp.ID != 0 {
		t.Log("Response with ID=0 would be parsed as response")
	} else {
		t.Log("Response with ID=0 would NOT be parsed as response (BUG!)")
	}
}

func TestPermissionResponseMarshaling(t *testing.T) {
	// Test that our response marshals correctly
	response := map[string]interface{}{
		"jsonrpc": "2.0",
		"id":      0,
		"result": PermissionResponse{
			Outcome: PermissionOutcome{
				Outcome:  "selected",
				OptionID: "allow",
			},
		},
	}

	data, err := json.Marshal(response)
	if err != nil {
		t.Fatalf("Failed to marshal response: %v", err)
	}

	expected := `{"id":0,"jsonrpc":"2.0","result":{"outcome":{"outcome":"selected","optionId":"allow"}}}`

	// JSON field order doesn't matter, so let's unmarshal and compare
	var got, want map[string]interface{}
	json.Unmarshal(data, &got)
	json.Unmarshal([]byte(expected), &want)

	if got["id"].(float64) != want["id"].(float64) {
		t.Errorf("ID mismatch: got %v, want %v", got["id"], want["id"])
	}

	if got["jsonrpc"] != want["jsonrpc"] {
		t.Errorf("jsonrpc mismatch: got %v, want %v", got["jsonrpc"], want["jsonrpc"])
	}

	gotResult := got["result"].(map[string]interface{})
	wantResult := want["result"].(map[string]interface{})
	if gotResult["optionId"] != wantResult["optionId"] {
		t.Errorf("optionId mismatch: got %v, want %v", gotResult["optionId"], wantResult["optionId"])
	}

	t.Logf("Marshaled response: %s", string(data))
}
