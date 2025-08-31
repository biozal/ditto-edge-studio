using System;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Input;
using CommunityToolkit.Mvvm.Input;
using EdgeStudio.Models;

namespace EdgeStudio.ViewModels
{
    public class EdgeStudioViewModel : INotifyPropertyChanged
    {
        private DittoDatabaseConfig? _selectedDatabase;
        private RelayCommand? _closeDatabaseCommand;

        public event PropertyChangedEventHandler? PropertyChanged;
        public event EventHandler? CloseDatabaseRequested;

        public DittoDatabaseConfig? SelectedDatabase
        {
            get => _selectedDatabase;
            set
            {
                if (_selectedDatabase != value)
                {
                    _selectedDatabase = value;
                    OnPropertyChanged();
                }
            }
        }

        public ICommand CloseDatabaseCommand => _closeDatabaseCommand ??= new RelayCommand(() => ExecuteCloseDatabase(null));

        private void ExecuteCloseDatabase(object? parameter)
        {
            CloseDatabaseRequested?.Invoke(this, EventArgs.Empty);
        }

        protected virtual void OnPropertyChanged([CallerMemberName] string? propertyName = null)
        {
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
        }
    }
}