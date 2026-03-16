using System.Threading.Tasks;
using EdgeStudio.Shared.Models;

namespace EdgeStudio.Shared.Data
{
    public interface IQueryService
    {
        Task<QueryExecutionResult> ExecuteLocalAsync(string dql);
    }
}
