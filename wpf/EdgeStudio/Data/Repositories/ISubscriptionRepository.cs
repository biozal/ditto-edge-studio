using EdgeStudio.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace EdgeStudio.Data.Repositories
{
    public interface ISubscriptionRepository
    {
        Task DeleteDittoSubscription(DittoDatabaseSubscription subscription); 
        Task SaveDittoSubscription(DittoDatabaseSubscription subscription);

    }
}
