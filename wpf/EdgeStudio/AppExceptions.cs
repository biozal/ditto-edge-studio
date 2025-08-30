using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace EdgeStudio
{
    public class InvalidStateException
        : Exception
    {
        public InvalidStateException(string? message) : base(message)
        {
        }
    }
}
