# Question 9: Farmer Cooperative Maize Deliveries

PostgreSQL. Run `solution.sql` from top to bottom. It creates its own schema `q9`.
Scheduled jobs use pg_cron.

## Index
`deliveries(farmer_id, delivered_on)`

A farmer's deliveries between two dates is an equality on farmer_id and a range on delivered_on. This column order returns exactly that range from the index without scanning other farmers' rows.

Note: pr_receive_delivery passes 0 for unit_rate and total_value because those columns are NOT NULL; the trigger overwrites them.
