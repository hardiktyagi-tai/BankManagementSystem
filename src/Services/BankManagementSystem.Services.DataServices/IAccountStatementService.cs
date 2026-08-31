namespace BankManagementSystem.Services.DataServices
{
    using System;
    using System.Collections.Generic;
    using System.Threading.Tasks;

    /// <summary>
    /// Produces account statements for a date range.
    /// </summary>
    public interface IAccountStatementService
    {
        /// <summary>
        /// Every transaction against the client's account between two dates.
        /// </summary>
        Task<IEnumerable<string>> GetStatementLinesAsync(string username, DateTime from, DateTime to);

        /// <summary>
        /// The closing balance at the end of the requested period.
        /// </summary>
        Task<decimal> GetClosingBalanceAsync(string username, DateTime asOf);

        /// <summary>
        /// Whether the account was overdrawn at any point in the period.
        /// </summary>
        Task<bool> WasOverdrawnAsync(string username, DateTime from, DateTime to);
    }
}
