"""Repeatable, idempotent demo seed (run AFTER migrations).

Seeds:
- 3 fictional customers + 1 fictional admin, Argon2-hashed passwords
- 4 fictional restaurants, each with 6 menu items (INR, integer minor units),
  including exactly one unavailable item so availability handling is real

Running it again converges to the same deterministic state. Existing
accounts keep their password unless --reset-passwords is passed (documented
in README). Usage inside Compose:

    docker compose run --rm seed
"""

from __future__ import annotations

import argparse
import asyncio
import logging
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.logging import configure_logging
from app.core.security import hash_password
from app.db.models.menu_item import MenuItem
from app.db.models.restaurant import Restaurant
from app.db.models.user import User
from app.db.session import session_scope

logger = logging.getLogger("quickbite.seed")

# (email, full_name, role, password) — fictional, local-only, documented in README.
SEED_ACCOUNTS: list[dict[str, Any]] = [
    {
        "id": "user_alice",
        "email": "alice@quickbite.dev",
        "full_name": "Alice Sharma",
        "role": "customer",
        "password": "quickbite!alice1",
    },
    {
        "id": "user_bob",
        "email": "bob@quickbite.dev",
        "full_name": "Bob Verma",
        "role": "customer",
        "password": "quickbite!bob1",
    },
    {
        "id": "user_carol",
        "email": "carol@quickbite.dev",
        "full_name": "Carol D'Souza",
        "role": "customer",
        "password": "quickbite!carol1",
    },
    {
        "id": "user_admin",
        "email": "admin@quickbite.dev",
        "full_name": "QuickBite Admin",
        "role": "admin",
        "password": "quickbite!admin1",
    },
]

# (id, name, description, [(id, name, description, price_minor, available, sort)])
SEED_RESTAURANTS: list[dict[str, Any]] = [
    {
        "id": "rest_spice_route",
        "name": "Spice Route Kitchen",
        "description": "North Indian classics, slow-simmered curries and tandoor breads.",
        "items": [
            (
                "item_dal_makhani",
                "Dal Makhani",
                "Black lentils simmered overnight with butter.",
                22000,
                True,
                1,
            ),
            (
                "item_tandoori_chicken",
                "Tandoori Chicken",
                "Char-grilled chicken with smoky spices.",
                38000,
                True,
                2,
            ),
            (
                "item_hyderabadi_biryani",
                "Hyderabadi Biryani",
                "Layered basmati rice with saffron.",
                32000,
                True,
                3,
            ),
            (
                "item_paneer_tikka",
                "Paneer Tikka",
                "Cottage cheese grilled with peppers.",
                26000,
                True,
                4,
            ),
            (
                "item_garlic_naan",
                "Garlic Naan",
                "Tandoor bread with garlic and coriander.",
                6000,
                True,
                5,
            ),
            (
                "item_mango_lassi",
                "Mango Lassi",
                "Chilled yogurt drink with alphonso mango.",
                12000,
                False,
                6,
            ),
        ],
    },
    {
        "id": "rest_coastal_catch",
        "name": "Coastal Catch",
        "description": "Coastal seafood curries, grills and fry-ups.",
        "items": [
            (
                "item_fish_curry",
                "Fish Curry",
                "Coconut-kokum curry with catch of the day.",
                34000,
                True,
                1,
            ),
            (
                "item_prawns_garlic",
                "Garlic Butter Prawns",
                "Juicy prawns tossed in garlic butter.",
                42000,
                True,
                2,
            ),
            (
                "item_grilled_pomfret",
                "Grilled Pomfret",
                "Whole pomfret, tandoor-grilled.",
                52000,
                True,
                3,
            ),
            ("item_crab_masala", "Crab Masala", "Fresh crab in a fiery masala.", 48000, True, 4),
            (
                "item_seafood_platter",
                "Seafood Platter",
                "Prawns, fish, calamari and sides.",
                69000,
                True,
                5,
            ),
            ("item_coconut_kheer", "Coconut Kheer", "Slow-cooked coconut pudding.", 12000, True, 6),
        ],
    },
    {
        "id": "rest_bella_napoli",
        "name": "Bella Napoli",
        "description": "Wood-fired pizzas and Roman-style pasta.",
        "items": [
            (
                "item_margherita_pizza",
                "Margherita Pizza",
                "San Marzano tomato, fior di latte, basil.",
                28000,
                True,
                1,
            ),
            (
                "item_pepperoni_pizza",
                "Pepperoni Pizza",
                "Double pepperoni with chilli honey.",
                36000,
                True,
                2,
            ),
            (
                "item_carbonara",
                "Spaghetti Carbonara",
                "Guanciale, pecorino, black pepper.",
                34000,
                True,
                3,
            ),
            (
                "item_tiramisu",
                "Tiramisu",
                "Espresso-soaked savoiardi with mascarpone.",
                21000,
                True,
                4,
            ),
            ("item_garlic_bread", "Garlic Bread", "Oven-baked with herb butter.", 15000, True, 5),
            (
                "item_bbq_chicken_pizza",
                "BBQ Chicken Pizza",
                "Temporarily off the menu.",
                41000,
                False,
                6,
            ),
        ],
    },
    {
        "id": "rest_sweet_crumb",
        "name": "Sweet Crumb Patisserie",
        "description": "Small-batch cakes, pastries and specialty coffee.",
        "items": [
            (
                "item_chocolate_truffle",
                "Chocolate Truffle Slice",
                "Dark chocolate ganache layers.",
                25000,
                True,
                1,
            ),
            (
                "item_red_velvet_slice",
                "Red Velvet Slice",
                "Cream cheese frosting, cocoa crumb.",
                23000,
                True,
                2,
            ),
            (
                "item_baked_cheesecake",
                "Baked Cheesecake",
                "Vanilla bean, biscuit base.",
                28000,
                True,
                3,
            ),
            (
                "item_butter_croissant",
                "Butter Croissant",
                "Laminated over three days.",
                9000,
                True,
                4,
            ),
            (
                "item_fudge_brownie",
                "Fudge Brownie",
                "Salted dark chocolate brownie.",
                15000,
                True,
                5,
            ),
            ("item_matcha_latte", "Matcha Latte", "Ceremonial matcha, oat milk.", 18000, True, 6),
        ],
    },
]


async def seed_all(session: AsyncSession, *, reset_passwords: bool = False) -> dict[str, int]:
    counts = {"users_created": 0, "users_updated": 0, "restaurants": 0, "menu_items": 0}

    for account in SEED_ACCOUNTS:
        user = await session.get(User, account["id"])
        if user is None:
            session.add(
                User(
                    id=account["id"],
                    email=account["email"],
                    password_hash=hash_password(account["password"]),
                    full_name=account["full_name"],
                    role=account["role"],
                    is_active=True,
                )
            )
            counts["users_created"] += 1
        else:
            user.email = account["email"]
            user.full_name = account["full_name"]
            user.role = account["role"]
            user.is_active = True
            if reset_passwords:
                user.password_hash = hash_password(account["password"])
            counts["users_updated"] += 1
    await session.flush()

    for restaurant_data in SEED_RESTAURANTS:
        restaurant = await session.get(Restaurant, restaurant_data["id"])
        if restaurant is None:
            restaurant = Restaurant(
                id=restaurant_data["id"],
                name=restaurant_data["name"],
                description=restaurant_data["description"],
                currency="INR",
                is_available=True,
            )
            session.add(restaurant)
        else:
            restaurant.name = restaurant_data["name"]
            restaurant.description = restaurant_data["description"]
            restaurant.is_available = True
        counts["restaurants"] += 1
        await session.flush()

        for item_id, name, description, price_minor, available, sort_order in restaurant_data[
            "items"
        ]:
            item = await session.get(MenuItem, item_id)
            if item is None:
                session.add(
                    MenuItem(
                        id=item_id,
                        restaurant_id=restaurant.id,
                        name=name,
                        description=description,
                        price_amount_minor=price_minor,
                        currency="INR",
                        is_available=available,
                        sort_order=sort_order,
                    )
                )
            else:
                item.name = name
                item.description = description
                item.price_amount_minor = price_minor
                item.is_available = available
                item.sort_order = sort_order
            counts["menu_items"] += 1

    await session.flush()
    return counts


async def _run(reset_passwords: bool) -> None:
    async with session_scope() as session:
        counts = await seed_all(session, reset_passwords=reset_passwords)
    logger.info("seed complete", extra={"result": str(counts)})


def main() -> None:
    parser = argparse.ArgumentParser(description="Seed QuickBite demo data (idempotent).")
    parser.add_argument(
        "--reset-passwords",
        action="store_true",
        help="Force-reset seeded account passwords to the documented demo values.",
    )
    args = parser.parse_args()

    settings = get_settings()
    configure_logging(settings.log_level, service="seed")
    asyncio.run(_run(args.reset_passwords))


if __name__ == "__main__":
    main()
