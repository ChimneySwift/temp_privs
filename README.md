# Temp Privs
Overwrites the default grant, grantme and revoke chatcommands to add revoke or grant expiration.

## Usage
The default commands still work for permanant grants and revokes, however you can optionally select a time period whereby the revoke/granting will be reverted.

`grant <playername> <time-optional> <privstring>`

`grantme <time-optional> <privstring>`

`revoke <playername> <time-optional> <privstring>`

`<time>` syntax:

- 1s - one second.
- 1m - one minute.
- 1h - one hour.
- 1D - one day (24 hours).
- 1W - one week (7 days).
- 1M - one month (30 days).
- 1Y - one year (360 days).
