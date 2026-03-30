# Fix: EXPLAIN Output Blank in Query Metrics Inspector

## Problem
The Query Metrics inspector panel shows blank EXPLAIN Output and incorrectly shows "Not Indexed" badge even when a query uses an index.

## Root Cause Analysis

### SwiftUI implementation (working)
```swift
let explainResults = try await ditto.store.execute(query: "EXPLAIN \(query)")
if let firstItem = explainResults.items.first {
    let cleaned = firstItem.value.compactMapValues { $0 }
    let data = try JSONSerialization.data(
        withJSONObject: cleaned,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    )
    return String(data: data, encoding: .utf8) ?? "No explain output"
}
```

Key: uses `firstItem.value` → compact-maps nils → `JSONSerialization` (native macOS/iOS serializer).

### .NET implementation (broken)
The C# code has gone through several failed attempts:
1. `JsonSerializer.Serialize(item.Value)` — fails because `item.Value` calls `Materialize()` which calls `GetNormalizedObject() as Dictionary<string, object>`. If this cast fails or if nested types can't be serialized by `System.Text.Json`, it throws silently.
2. `item.JsonString()` — calls `dittoffi_query_result_item_json` FFI function which may return null for EXPLAIN items, throwing `DittoException("can't return JSON string for item")`.
3. Both approaches fail, inner catches set `json = string.Empty`, returns "".

### Why `result.Items.Count == 0` is NOT the issue
The native Ditto library clearly returns 1 EXPLAIN result item (confirmed via MCP tool). The `Items` list is populated. The problem is downstream — how we extract the JSON from the item.

### Root cause: CBOR item extraction approach
The .NET SDK exposes two ways to get item content:
- `item.Value` → `Materialize()` → `CBORObject.GetNormalizedObject() as Dictionary<string, object>` → can fail
- `item.JsonString()` → `dittoffi_query_result_item_json` → can fail for EXPLAIN items
- `item.CborData()` → `dittoffi_query_result_item_cbor` → reads raw CBOR bytes → `CBORObject.Read()` → **always works if item exists**

The correct approach: `item.CborData()` (reads raw CBOR) → `cbor.ToJSONString()` (CBOR→JSON, PeterO.CBOR built-in) → `JsonDocument.Parse` → `JsonSerializer.Serialize` (pretty-print). This matches what Swift's `JSONSerialization` does internally — working at the raw serialization level rather than through an intermediate dictionary representation.

## Implementation

### File: `EdgeStudio.Shared/Data/DittoQueryService.cs`

Replace `RunExplainAsync` to use `item.CborData().ToJSONString()` as the primary extraction method, mirroring the Swift approach of going directly to the serialization layer:

```csharp
private static async Task<string> RunExplainAsync(string dql, DittoSDK.Ditto ditto)
{
    var trimmed = dql.TrimStart();
    if (trimmed.StartsWith("EXPLAIN", StringComparison.OrdinalIgnoreCase))
        return string.Empty;
    try
    {
        var result = await ditto.Store.ExecuteAsync($"EXPLAIN {dql}");
        if (result.Items.Count == 0)
        {
            result.Dispose();
            return string.Empty;
        }
        var item = result.Items[0];
        try
        {
            // Mirror Swift: firstItem.value → JSONSerialization
            // In .NET: CborData() reads raw CBOR → ToJSONString() converts to JSON
            // This is more reliable than item.Value (GetNormalizedObject cast) or item.JsonString() (FFI)
            var rawJson = item.CborData().ToJSONString();
            item.Dematerialize();
            result.Dispose();
            using var doc = JsonDocument.Parse(rawJson);
            return JsonSerializer.Serialize(doc.RootElement, PrettyOptions);
        }
        catch
        {
            item.Dematerialize();
            result.Dispose();
            return string.Empty;
        }
    }
    catch (Exception ex)
    {
        return $"EXPLAIN failed: {ex.Message}";
    }
}
```

`CBORObject.ToJSONString()` is part of the PeterO.CBOR public API, available as a transitive dependency from the Ditto NuGet package. No additional package reference needed.

## Verification
After fix, run a SELECT query with an index. The inspector should show:
- "Indexed" badge (not "Not Indexed")
- EXPLAIN Output showing the full plan JSON with `indexScan` operator
