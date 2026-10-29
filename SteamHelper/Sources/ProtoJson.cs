#nullable enable
using System;
using System.Collections;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;

namespace OWESteamHelper
{
    /// JSON for SteamKit's protobuf messages in the shape Steam's Web API uses for the same
    /// messages, so the app reads one format: proto field names, 64-bit integers as strings, and
    /// only the fields Steam set (protobuf-net's `ShouldSerialize…`), without empty lists.
    static class ProtoJson
    {
        public static readonly JsonSerializerOptions Options = MakeOptions();

        static JsonSerializerOptions MakeOptions()
        {
            var options = new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = false,
                // Repeated fields are get-only lists: fill them instead of replacing them.
                PreferredObjectCreationHandling = JsonObjectCreationHandling.Populate,
                UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
                TypeInfoResolver = new DefaultJsonTypeInfoResolver { Modifiers = { OnlySetFields } },
            };
            options.Converters.Add(new StringInt64Converter<ulong>(ulong.Parse, v => v.ToString()));
            options.Converters.Add(new StringInt64Converter<long>(long.Parse, v => v.ToString()));
            return options;
        }

        static void OnlySetFields(JsonTypeInfo info)
        {
            if (info.Kind != JsonTypeInfoKind.Object) return;
            for (var i = info.Properties.Count - 1; i >= 0; i--)
            {
                var property = info.Properties[i];
                // protobuf-net's extension data and similar internals aren't fields.
                if (property.Name.StartsWith("__", StringComparison.Ordinal))
                {
                    info.Properties.RemoveAt(i);
                    continue;
                }
                var shouldSerialize = info.Type.GetMethod("ShouldSerialize" + property.Name,
                    BindingFlags.Public | BindingFlags.Instance, Type.EmptyTypes);
                if (shouldSerialize != null)
                    property.ShouldSerialize = (owner, _) => (bool)shouldSerialize.Invoke(owner, null)!;
                else if (typeof(ICollection).IsAssignableFrom(property.PropertyType))
                    property.ShouldSerialize = (_, value) => value is ICollection { Count: > 0 };
            }
        }

        /// Steam's Web API writes 64-bit integers as strings; reading takes either.
        sealed class StringInt64Converter<T>(Func<string, T> parse, Func<T, string> format) : JsonConverter<T>
        {
            public override T Read(ref Utf8JsonReader reader, Type typeToConvert, JsonSerializerOptions options) =>
                reader.TokenType == JsonTokenType.String
                    ? parse(reader.GetString()!)
                    : parse(System.Text.Encoding.UTF8.GetString(reader.ValueSpan));

            public override void Write(Utf8JsonWriter writer, T value, JsonSerializerOptions options) =>
                writer.WriteStringValue(format(value));
        }
    }
}
