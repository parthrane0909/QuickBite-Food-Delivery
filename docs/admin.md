# Admin management and large catalogue

## Authorization boundary

Admin management is enforced by FastAPI's `AdminDep`; hiding a Flutter route
does not grant access. Missing/expired authentication returns `401`, while a
signed-in customer calling a management route receives `403`. The original
cross-customer order overview and aggregate reliability counters remain
available. Order detail is observational and has no admin state mutation.

Admins can also shop through the regular customer routes using their own user
identity. The server uses that same identity as `customer_id` for checkout and
returns only that identity's orders. Admin access to the management APIs is
unchanged, and no account impersonation or alternate embedded credentials are
used. Cart and uncertain checkout state are namespaced by signed-in user.

## Management behavior

- Restaurant and menu lists are paginated (maximum page size 100), searchable,
  and have deterministic ordering. Restaurant active state is filterable.
- Restaurant, menu, and customer changes create an `admin_audit_logs` row in
  the same transaction. Audit data includes actor, action, target, timestamp,
  and changed field names; it excludes passwords and hashes.
- Deactivation is a soft availability/account-state change. Historical orders,
  customer references, and order-item name/price snapshots are preserved.
- Menu prices are positive integer INR minor units. Menu items cannot be
  reassigned across restaurants. Admin edit forms send the previous
  `updated_at`; stale edits return a conflict rather than silently overwriting
  a concurrent edit.
- Driver total means rows in the persistent fictional `drivers` roster.
  Assigned-order counts are shown separately from that total.
- Restaurant rows include PostgreSQL-derived menu counts, order counts,
  distinct ordering customers, last-order time, and total accepted order
  value. That value sums amounts accepted into order processing; it is not a
  statement of collected payments.
- Customer records include order count and last-order time as activity
  statistics. Order inspection remains read-only and uses stored item-price
  snapshots.

## Catalogue seed

The regular fixture seed remains small and stable for tests. To add the
deterministic showcase set after migrations and services are ready, run:

```bash
docker compose exec api python -m scripts.seed_large_catalogue
```

The command is explicit, batched, additive, and repeatable; it does not run at
API or worker startup. Existing fixture IDs, users, orders, order-item
snapshots, and fixture prices are protected. The showcase set currently has
2,000 restaurants and 19,992 menu items (showcase restaurants receive ten
cuisine-matched items; protected fixture restaurants retain their existing
menus and receive only their two safe showcase supplements). A second run
reports zero new records. Migrations add restaurant cuisine/search indexes,
the driver roster, and the admin audit table without dropping data. Trigram
indexes back case-insensitive partial matches across restaurant names,
cuisines, dish names, and descriptions.

## Image sourcing

The bundled demo image library contains 45 locally stored, optimized photos:
16 cuisine-family images, 24 dish images, 4 fixture restaurant images, and one
welcome hero. Every asset has a record in
[`frontend/assets/food/CREDITS.json`](../frontend/assets/food/CREDITS.json),
including source page, author, license, dimensions, size, checksum, local path,
and transformations. Human-readable credits are in
[`frontend/assets/food/CREDITS.md`](../frontend/assets/food/CREDITS.md) and in
the account screen. The larger catalogue maps to relevant cuisine-family
photos and selected exact dish matches; it does not claim a unique photo for
every one of the 19,992 menu items. Catalogue media is still bundled with the
Flutter app rather than served from a dedicated media service.

## Useful API routes

See [`api.md`](api.md) for the full contract. Admin pages use
`/api/v1/admin/summary`, `/orders`, `/orders/{id}`, `/restaurants`,
`/restaurants/{id}/menu`, `/customers`, `/customers/{id}/orders`, and
`/drivers`. Mutations use POST/PATCH and safe `deactivate` actions under the
same authenticated API client.
