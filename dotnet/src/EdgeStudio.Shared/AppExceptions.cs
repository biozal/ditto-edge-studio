using System;

namespace EdgeStudio.Shared
{
    public class InvalidStateException
        : Exception
    {
        public InvalidStateException(string? message) : base(message)
        {
        }
    }

    public class DeserializeException
    : Exception
    {
        public DeserializeException(string? message) : base(message)
        {
        }
    }
}
