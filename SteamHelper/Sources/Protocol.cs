// SPDX-License-Identifier: GPL-2.0-or-later
#nullable enable
using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading;

namespace OWESteamHelper
{
    /// One request from the app: a line of JSON, `{"id": 1, "method": "logOn", "params": {...}}`.
    sealed record Request(long Id, string Method, JsonElement Params);

    /// A failure the app tells apart by `Code`; `EResult` is Steam's, when Steam gave one.
    sealed class HelperException(string code, string message, int? eresult = null) : Exception(message)
    {
        public string Code { get; } = code;
        public int? EResult { get; } = eresult;
    }

    /// Error codes the app reads.
    static class ErrorCode
    {
        public const string InvalidRequest = "invalidRequest";
        public const string UnknownMethod = "unknownMethod";
        public const string NotLoggedOn = "notLoggedOn";
        /// The refresh token was refused (revoked, expired or signed out): the user signs in again.
        public const string TokenRejected = "tokenRejected";
        public const string WrongPassword = "wrongPassword";
        public const string Cancelled = "cancelled";
        public const string Network = "network";
        /// Steam answered with a failing EResult.
        public const string Steam = "steam";
        public const string Internal = "internal";
    }

    /// Writes the helper's side of the protocol to stdout: one JSON object per line, either a
    /// response (`id` with `result` or `error`) or an event (`event`, and the `id` it belongs to).
    sealed class ProtocolWriter(TextWriter output)
    {
        readonly Lock gate = new();

        public void Result(long id, JsonNode? result) =>
            Write(new JsonObject { ["id"] = id, ["result"] = result ?? new JsonObject() });

        public void Error(long? id, HelperException error)
        {
            var body = new JsonObject { ["code"] = error.Code, ["message"] = error.Message };
            if (error.EResult is int eresult) body["eresult"] = eresult;
            Write(new JsonObject { ["id"] = id, ["error"] = body });
        }

        public void Event(long? id, string name, JsonObject? fields = null)
        {
            var message = new JsonObject { ["event"] = name };
            if (id is long requestID) message["id"] = requestID;
            if (fields != null)
                foreach (var (key, value) in fields) message[key] = value?.DeepClone();
            Write(message);
        }

        void Write(JsonObject message)
        {
            var line = message.ToJsonString();
            lock (gate)
            {
                output.WriteLine(line);
                output.Flush();
            }
        }
    }

    static class RequestParser
    {
        /// Reads one request line; a line that isn't one throws `invalidRequest` with the id when
        /// the line had one.
        public static Request Parse(string line, out long? id)
        {
            id = null;
            JsonElement root;
            try
            {
                root = JsonDocument.Parse(line).RootElement.Clone();
            }
            catch (JsonException e)
            {
                throw new HelperException(ErrorCode.InvalidRequest, $"Not JSON: {e.Message}");
            }
            if (root.ValueKind != JsonValueKind.Object)
                throw new HelperException(ErrorCode.InvalidRequest, "A request is a JSON object.");
            if (root.TryGetProperty("id", out var idElement) && idElement.TryGetInt64(out var parsed))
                id = parsed;
            if (id is not long requestID)
                throw new HelperException(ErrorCode.InvalidRequest, "A request needs a numeric id.");
            if (!root.TryGetProperty("method", out var method) || method.ValueKind != JsonValueKind.String)
                throw new HelperException(ErrorCode.InvalidRequest, "A request needs a method.");
            var parameters = root.TryGetProperty("params", out var p) ? p : JsonDocument.Parse("{}").RootElement;
            if (parameters.ValueKind != JsonValueKind.Object)
                throw new HelperException(ErrorCode.InvalidRequest, "params must be an object.");
            return new Request(requestID, method.GetString()!, parameters);
        }

        public static string RequiredString(this JsonElement parameters, string name)
        {
            if (parameters.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
                && !string.IsNullOrEmpty(value.GetString()))
                return value.GetString()!;
            throw new HelperException(ErrorCode.InvalidRequest, $"Missing string parameter \"{name}\".");
        }

        public static string? OptionalString(this JsonElement parameters, string name) =>
            parameters.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
                ? value.GetString() : null;

        public static long RequiredInt64(this JsonElement parameters, string name)
        {
            if (parameters.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number
                && value.TryGetInt64(out var number))
                return number;
            throw new HelperException(ErrorCode.InvalidRequest, $"Missing number parameter \"{name}\".");
        }
    }
}
