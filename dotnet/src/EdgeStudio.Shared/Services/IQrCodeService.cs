using System.Collections.Generic;
using EdgeStudio.Shared.Models;

namespace EdgeStudio.Shared.Services
{
    public interface IQrCodeService
    {
        /// <summary>
        /// Encodes a database config and optional favorites into an EDS2 payload string.
        /// Trims oldest favorites until the payload is within 2200 bytes.
        /// </summary>
        string Encode(DittoDatabaseConfig config, IEnumerable<string> favoriteQueries);

        /// <summary>
        /// Decodes an EDS2 payload string (or legacy v1 plain JSON) into a config and favorites list.
        /// Returns null if the payload cannot be parsed.
        /// </summary>
        (DittoDatabaseConfig config, List<string> favorites)? Decode(string payload);
    }
}
