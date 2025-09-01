using EdgeStudio.Models;
using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace EdgeStudio.Data
{
    public interface ISystemService
    {
        void CloseSelectedDatabase();
        void RegisterLocalObservers(ObservableCollection<SyncStatusInfo> syncStatusInfos, Action<string> errorMessage);
    }
}
