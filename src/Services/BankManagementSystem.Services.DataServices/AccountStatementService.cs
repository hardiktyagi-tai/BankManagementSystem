namespace BankManagementSystem.Services.DataServices
{
    using System;
    using System.Collections.Generic;
    using System.Globalization;
    using System.Linq;
    using System.Threading.Tasks;

    /// <summary>
    /// Builds a human-readable account statement for a client over a date range.
    /// Self-contained: it formats the lines it is given rather than reaching
    /// into a repository, so it can be unit-tested without a database.
    /// </summary>
    public class AccountStatementService : IAccountStatementService
    {
        private const string LineFormat = "{0:yyyy-MM-dd}  {1,-24}  {2,12:N2}";

        private readonly IDictionary<string, IList<Tuple<DateTime, string, decimal>>> entries;

        public AccountStatementService()
        {
            this.entries = new Dictionary<string, IList<Tuple<DateTime, string, decimal>>>();
        }

        /// <summary>
        /// Records one movement against a client's account.
        /// </summary>
        public void Record(string username, DateTime occurredOn, string description, decimal amount)
        {
            if (string.IsNullOrWhiteSpace(username))
            {
                throw new ArgumentException("A username is required.", nameof(username));
            }

            if (!this.entries.ContainsKey(username))
            {
                this.entries[username] = new List<Tuple<DateTime, string, decimal>>();
            }

            this.entries[username].Add(Tuple.Create(occurredOn, description, amount));
        }

        /// <inheritdoc />
        public Task<IEnumerable<string>> GetStatementLinesAsync(string username, DateTime from, DateTime to)
        {
            if (string.IsNullOrWhiteSpace(username))
            {
                throw new ArgumentException("A username is required to build a statement.", nameof(username));
            }

            if (to < from)
            {
                throw new ArgumentException("The end of the period cannot precede its start.", nameof(to));
            }

            IEnumerable<string> lines = this.EntriesFor(username)
                .Where(e => e.Item1 >= from && e.Item1 <= to)
                .OrderBy(e => e.Item1)
                .Select(e => string.Format(CultureInfo.InvariantCulture, LineFormat, e.Item1, e.Item2, e.Item3))
                .ToList();

            return Task.FromResult(lines);
        }

        /// <inheritdoc />
        public Task<decimal> GetClosingBalanceAsync(string username, DateTime asOf)
        {
            decimal balance = this.EntriesFor(username)
                .Where(e => e.Item1 <= asOf)
                .Sum(e => e.Item3);

            return Task.FromResult(balance);
        }

        private IEnumerable<Tuple<DateTime, string, decimal>> EntriesFor(string username)
        {
            return this.entries.ContainsKey(username)
                ? this.entries[username]
                : Enumerable.Empty<Tuple<DateTime, string, decimal>>();
        }
    }
}
