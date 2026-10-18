"""Add a deterministic 2,000-restaurant showcase catalogue (never auto-run).

Only inserts records with stable showcase IDs. It never updates seeded demo
fixtures, admin changes, users, or historical orders. One transaction makes a
partial run all-or-nothing. Run after migrations:
    docker compose exec api python -m scripts.seed_large_catalogue
"""

from __future__ import annotations

import argparse
import asyncio
import logging

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert

from app.core.config import get_settings
from app.core.logging import configure_logging
from app.db.models.menu_item import MenuItem
from app.db.models.restaurant import Restaurant
from app.db.session import session_scope

logger = logging.getLogger("quickbite.catalogue")
TARGET_RESTAURANTS = 2_000
BATCH_SIZE = 1_000

# Eight cuisine-specific base dishes per restaurant plus two additional
# cuisine-specific plates. Existing showcase rows are completed additively on
# rerun; no existing menu item or historical order snapshot is overwritten.
# Names/descriptions are curated and prices are integer INR paise.
FAMILIES: tuple[tuple[str, str, str, tuple[tuple[str, str, int], ...]], ...] = (
    (
        "North Indian",
        "Saffron Courtyard",
        "Slow-cooked Punjabi favourites and tandoor breads.",
        (
            (
                "Dal Makhani",
                "Black lentils simmered overnight with tomato, cream and warming spices.",
                24500,
            ),
            (
                "Paneer Tikka",
                "Char-grilled paneer with peppers, hung curd and kasuri methi.",
                28500,
            ),
            (
                "Amritsari Chole",
                "Chickpeas cooked with tea-blackened spices, ginger and fresh coriander.",
                22000,
            ),
            (
                "Tandoori Chicken",
                "Yogurt-marinated chicken roasted in a clay oven until smoky.",
                36500,
            ),
            ("Butter Naan", "Soft tandoor-baked bread brushed with cultured butter.", 6500),
            ("Palak Paneer", "Paneer folded through a smooth spinach and garlic gravy.", 25500),
            ("Jeera Rice", "Long-grain basmati steamed with cumin and whole spices.", 14500),
            ("Gulab Jamun", "Warm khoya dumplings soaked in cardamom sugar syrup.", 12500),
        ),
    ),
    (
        "South Indian",
        "Mango Leaf House",
        "Regional South Indian breakfasts, dosas and homestyle meals.",
        (
            (
                "Masala Dosa",
                "Crisp rice-lentil crepe with spiced potato, coconut chutney and sambar.",
                18500,
            ),
            (
                "Ghee Podi Idli",
                "Steamed rice cakes tossed with lentil podi and fragrant ghee.",
                15500,
            ),
            (
                "Mysore Masala Dosa",
                "Chilli-garlic chutney, spiced potato and crisp fermented batter.",
                21000,
            ),
            (
                "Medu Vada",
                "Golden urad dal fritters served with coconut chutney and sambar.",
                14500,
            ),
            (
                "Lemon Rice",
                "Fluffy rice brightened with lemon, curry leaves and roasted peanuts.",
                17500,
            ),
            (
                "Kerala Vegetable Stew",
                "Seasonal vegetables simmered gently in coconut milk.",
                24500,
            ),
            (
                "Curd Rice",
                "Soft rice with cultured yogurt, ginger and a mustard seed tempering.",
                15500,
            ),
            ("Filter Coffee", "South Indian coffee decoction poured with steamed milk.", 9000),
        ),
    ),
    (
        "Italian",
        "Olive & Ember",
        "Hand-stretched pizzas, slow sauces and fresh pasta.",
        (
            (
                "Margherita Pizza",
                "Tomato, mozzarella and basil on a blistered, hand-stretched base.",
                32000,
            ),
            ("Penne Arrabbiata", "Penne in a lively tomato and chilli sauce with parsley.", 28500),
            (
                "Mushroom Risotto",
                "Arborio rice stirred with roasted mushrooms and parmesan.",
                36500,
            ),
            (
                "Basil Pesto Linguine",
                "Linguine with basil pesto, parmesan and toasted pine nuts.",
                34500,
            ),
            (
                "Roasted Vegetable Lasagne",
                "Layered pasta, slow tomato sauce and seasonal vegetables.",
                38500,
            ),
            (
                "Garlic Focaccia",
                "Olive-oil focaccia baked with roasted garlic and rosemary.",
                14500,
            ),
            ("Four Cheese Pizza", "Mozzarella, gorgonzola, ricotta and parmesan on tomato.", 39500),
            ("Tiramisu", "Espresso-soaked sponge layered with mascarpone and cocoa.", 22500),
        ),
    ),
    (
        "Chinese",
        "Jade Lantern Kitchen",
        "Wok-fired noodles, rice and balanced Chinese-style plates.",
        (
            (
                "Vegetable Hakka Noodles",
                "Wok-tossed noodles with cabbage, spring onion and crisp vegetables.",
                21500,
            ),
            (
                "Chilli Garlic Fried Rice",
                "Steamed rice stir-fried with garlic, chilli and seasonal vegetables.",
                22500,
            ),
            (
                "Ginger Sesame Tofu",
                "Crisp tofu glazed with ginger, sesame and a savoury soy sauce.",
                28500,
            ),
            (
                "Cantonese Mushroom Bowl",
                "Rice with mushrooms, greens and a light ginger-soy sauce.",
                27500,
            ),
            (
                "Vegetable Spring Rolls",
                "Crisp pastry rolls filled with cabbage and glass noodles.",
                16500,
            ),
            ("Hot and Sour Soup", "Peppery broth with mushrooms, tofu and bamboo shoots.", 14500),
            (
                "Szechuan Paneer",
                "Paneer and peppers coated in a tangy house-made chilli sauce.",
                29500,
            ),
            ("Scallion Pancakes", "Flaky griddled pancakes layered with fresh scallions.", 18500),
        ),
    ),
    (
        "Indo-Chinese",
        "Chilli Willow",
        "Familiar Indo-Chinese wok dishes with house-made sauces.",
        (
            (
                "Gobi Manchurian",
                "Crisp cauliflower tossed with ginger, garlic and tangy sauce.",
                23500,
            ),
            (
                "Schezwan Veg Noodles",
                "Noodles wok-tossed with vegetables and a bold chilli-garlic sauce.",
                22500,
            ),
            (
                "Chilli Paneer",
                "Paneer, peppers and onion glazed in a sweet-hot Indo-Chinese sauce.",
                29500,
            ),
            (
                "Triple Schezwan Rice",
                "Rice, noodles and vegetables finished with chilli-garlic sauce.",
                28500,
            ),
            (
                "Crispy Corn Chilli",
                "Golden corn kernels tossed with peppers and spring onion.",
                21500,
            ),
            ("Veg Manchow Soup", "Spiced vegetable broth topped with crisp noodles.", 15500),
            (
                "Hakka Vegetable Rice",
                "Wok-fried rice with vegetables, garlic and spring onion.",
                21500,
            ),
            (
                "Honey Chilli Potato",
                "Crisp potato batons with sesame and a bright chilli glaze.",
                22500,
            ),
        ),
    ),
    (
        "Thai",
        "Lime & Lemongrass",
        "Aromatic Thai-inspired curries, noodles and herb-forward sides.",
        (
            (
                "Green Curry Tofu",
                "Coconut curry with tofu, basil, lime leaf and seasonal vegetables.",
                31500,
            ),
            (
                "Pad Thai Vegetables",
                "Rice noodles with tamarind, tofu, sprouts and roasted peanuts.",
                29500,
            ),
            (
                "Thai Basil Fried Rice",
                "Wok rice with Thai basil, garlic, chilli and vegetables.",
                27500,
            ),
            (
                "Red Curry Vegetables",
                "Red curry simmered with coconut milk and crisp vegetables.",
                31500,
            ),
            ("Tom Kha Soup", "Coconut broth brightened with galangal, lime and mushrooms.", 19500),
            ("Mango Sticky Rice", "Sweet coconut rice with ripe mango and toasted sesame.", 22500),
            ("Crispy Tofu Salad", "Herbs, greens and crisp tofu with a lime dressing.", 25500),
            (
                "Cashew Vegetable Stir-fry",
                "Seasonal vegetables with roasted cashews and ginger.",
                28500,
            ),
        ),
    ),
    (
        "Japanese-inspired",
        "Paper Crane Table",
        "Rice bowls, comforting broths and Japanese-inspired bites.",
        (
            (
                "Teriyaki Tofu Bowl",
                "Grilled tofu, rice and greens with a glossy house teriyaki.",
                29500,
            ),
            ("Miso Mushroom Ramen", "Noodles in a slow-simmered miso broth with mushrooms.", 33500),
            (
                "Vegetable Gyoza",
                "Pan-seared dumplings filled with cabbage, ginger and chives.",
                19500,
            ),
            (
                "Crispy Katsu Aubergine",
                "Panko aubergine with rice and a tangy katsu-style sauce.",
                28500,
            ),
            (
                "Sesame Soba Salad",
                "Buckwheat noodles, cucumber and greens with sesame dressing.",
                26500,
            ),
            ("Edamame with Sea Salt", "Warm young soybeans finished with flaky salt.", 12500),
            ("Onigiri Pair", "Seasoned rice parcels wrapped in crisp nori.", 18500),
            ("Matcha Cheesecake", "Creamy baked cheesecake with a gentle matcha finish.", 22500),
        ),
    ),
    (
        "Mediterranean",
        "Olive Grove Table",
        "Grilled vegetables, warm breads and bright Mediterranean bowls.",
        (
            (
                "Falafel Hummus Bowl",
                "Herbed falafel, hummus, grains and crunchy seasonal vegetables.",
                28500,
            ),
            (
                "Halloumi Grain Plate",
                "Grilled halloumi, lemon grains and a crisp herb salad.",
                33500,
            ),
            (
                "Roasted Aubergine Pita",
                "Smoky aubergine, tahini and pickled vegetables in warm pita.",
                25500,
            ),
            ("Greek Village Salad", "Tomato, cucumber, olives, feta and oregano dressing.", 26500),
            (
                "Lemon Herb Couscous",
                "Fluffy couscous with parsley, lemon and toasted almonds.",
                21500,
            ),
            ("Spinach Feta Borek", "Flaky pastry filled with spinach and tangy feta.", 19500),
            (
                "Harissa Chickpea Stew",
                "Chickpeas gently cooked with tomato and fragrant harissa.",
                27500,
            ),
            ("Pistachio Baklava", "Crisp filo layers with pistachio and a light syrup.", 16500),
        ),
    ),
    (
        "Burgers",
        "Copper Bun Co.",
        "Griddled burgers, crisp sides and house-made sauces.",
        (
            (
                "Classic Smash Burger",
                "Seared patty, cheddar, lettuce and house burger sauce.",
                32500,
            ),
            ("Crispy Paneer Burger", "Spiced crisp paneer, cabbage slaw and mint mayo.", 28500),
            (
                "Double Pepper Burger",
                "Two griddled patties with pepper relish and melted cheese.",
                42500,
            ),
            (
                "Mushroom Swiss Burger",
                "Roasted mushrooms, Swiss-style cheese and onion jam.",
                35500,
            ),
            (
                "Peri Peri Chicken Burger",
                "Grilled chicken, bright peri peri sauce and crunchy lettuce.",
                34500,
            ),
            ("Seasoned Potato Wedges", "Skin-on wedges with smoked paprika and herb salt.", 14500),
            ("Crispy Onion Rings", "Golden onion rings served with a peppery dip.", 15500),
            ("Chocolate Malt Shake", "Cold chocolate shake blended with malt and vanilla.", 18500),
        ),
    ),
    (
        "Bakery",
        "The Flour Room",
        "Small-batch bakes, laminated pastries and savoury pies.",
        (
            (
                "Butter Croissant",
                "Laminated pastry baked until crisp outside and tender within.",
                11000,
            ),
            (
                "Almond Pain au Chocolat",
                "Flaky pastry with dark chocolate and toasted almonds.",
                15500,
            ),
            ("Spinach Feta Danish", "Golden pastry filled with spinach and crumbled feta.", 17500),
            (
                "Sourdough Grilled Cheese",
                "Toasted sourdough with mature cheese and slow onion.",
                23500,
            ),
            ("Cinnamon Morning Bun", "Layered pastry rolled in cinnamon sugar.", 14500),
            ("Lemon Drizzle Loaf", "Soft lemon cake finished with a bright citrus glaze.", 16500),
            ("Mushroom Hand Pie", "Buttery pastry filled with thyme mushrooms.", 19500),
            ("Seasonal Fruit Tart", "Shortcrust shell, vanilla custard and seasonal fruit.", 22500),
        ),
    ),
    (
        "Seafood",
        "Tide & Tamarind",
        "Coastal seafood, grilled catch and coconut-rich curries.",
        (
            ("Goan Fish Curry", "Fish simmered in a coconut, chilli and kokum curry.", 38500),
            (
                "Garlic Butter Prawns",
                "Prawns seared with garlic, parsley and cultured butter.",
                46500,
            ),
            (
                "Grilled Coastal Pomfret",
                "Whole fish marinated with lime and roasted coastal spices.",
                54500,
            ),
            (
                "Pepper Calamari",
                "Tender calamari with cracked pepper and a crisp lemon finish.",
                39500,
            ),
            (
                "Kerala Fish Moilee",
                "Gentle coconut milk curry with ginger and curry leaves.",
                37500,
            ),
            (
                "Crab Pepper Masala",
                "Crab cooked with black pepper, tomato and fresh coriander.",
                52500,
            ),
            (
                "Prawn Coconut Rice",
                "Fragrant rice with prawns, coconut and toasted curry leaves.",
                42500,
            ),
            ("Sol Kadhi", "Cooling kokum and coconut drink with a delicate spice finish.", 9500),
        ),
    ),
    (
        "Desserts",
        "Sugar Maple Studio",
        "Layered desserts, chocolate bakes and seasonal sweets.",
        (
            (
                "Dark Chocolate Torte",
                "Dense chocolate cake finished with cocoa and berries.",
                24500,
            ),
            (
                "Baked Vanilla Cheesecake",
                "Creamy vanilla cheesecake on a toasted biscuit base.",
                26500,
            ),
            (
                "Salted Caramel Brownie",
                "Fudgy cocoa brownie with a ribbon of salted caramel.",
                18500,
            ),
            (
                "Raspberry Panna Cotta",
                "Silky cream-set vanilla pudding with tart raspberry.",
                21500,
            ),
            ("Pistachio Choux Bun", "Light choux pastry filled with pistachio cream.", 19500),
            ("Classic Tiramisu", "Coffee-soaked sponge, mascarpone and a dusting of cocoa.", 23500),
            ("Warm Apple Crumble", "Cinnamon apples under a buttery oat crumble.", 22500),
            ("Mango Kulfi", "Slow-reduced milk frozen with mango and cardamom.", 16500),
        ),
    ),
    (
        "Biryani",
        "Dum & Fragrant",
        "Layered dum biryani with fragrant rice and house-made accompaniments.",
        (
            (
                "Hyderabadi Chicken Dum Biryani",
                "Basmati layered with marinated chicken and saffron.",
                34500,
            ),
            (
                "Vegetable Dum Biryani",
                "Seasonal vegetables layered with mint and aged basmati.",
                27500,
            ),
            (
                "Lucknowi Mutton Biryani",
                "Awadhi-style mutton and rice cooked slowly under dum.",
                46500,
            ),
            (
                "Paneer Tikka Biryani",
                "Charred paneer layered with aromatic basmati and herbs.",
                31500,
            ),
            ("Egg Biryani", "Spiced eggs and basmati finished with fried onion.", 26500),
            ("Mirchi Salan", "Roasted chillies in a peanut and sesame gravy.", 14500),
            ("Cucumber Raita", "Cool yogurt with cucumber, mint and toasted cumin.", 9500),
            ("Double ka Meetha", "Slow-baked bread pudding with cardamom and nuts.", 16500),
        ),
    ),
    (
        "Sandwiches",
        "Market Lane Deli",
        "Freshly assembled sandwiches, salads and toasted melts.",
        (
            (
                "Roasted Vegetable Panini",
                "Grilled vegetables, basil spread and mozzarella in toasted bread.",
                24500,
            ),
            (
                "Paneer Tikka Sandwich",
                "Smoky paneer, pickled onion and mint yogurt on seeded bread.",
                26500,
            ),
            (
                "Classic Club Sandwich",
                "Layered toast with grilled chicken, egg and crisp greens.",
                29500,
            ),
            ("Avocado Lemon Toast", "Ripe avocado, lemon and chilli on sourdough.", 27500),
            ("Tuna Caper Melt", "Tuna, capers and melted cheese on toasted country bread.", 31500),
            ("Tomato Mozzarella Baguette", "Fresh mozzarella, ripe tomato and basil oil.", 28500),
            ("Crunchy Slaw Side", "Cabbage and carrot slaw with a light citrus dressing.", 9500),
            ("Brown Butter Cookie", "Soft-centred cookie with dark chocolate pieces.", 10500),
        ),
    ),
    (
        "Healthy bowls",
        "Green Field Kitchen",
        "Balanced grain bowls, fresh produce and thoughtful dressings.",
        (
            ("Roasted Pumpkin Bowl", "Roasted pumpkin, quinoa, greens and toasted seeds.", 28500),
            ("Protein Lentil Bowl", "Warm lentils, brown rice, greens and lemon tahini.", 26500),
            ("Avocado Edamame Bowl", "Edamame, avocado, cucumber and sesame brown rice.", 31500),
            (
                "Tandoori Paneer Greens",
                "Spiced paneer, crisp greens and a cooling yogurt dressing.",
                32500,
            ),
            (
                "Citrus Chickpea Salad",
                "Chickpeas, orange, herbs and crunchy seasonal vegetables.",
                24500,
            ),
            ("Miso Tofu Grain Bowl", "Miso-glazed tofu, grains and steamed vegetables.", 29500),
            ("Warm Millet Khichdi", "Soft-cooked millet and lentils with gentle spices.", 22500),
            ("Cocoa Date Energy Bites", "Dates, almonds and cocoa rolled into small bites.", 12500),
        ),
    ),
    (
        "Korean-inspired",
        "Seoul Garden Table",
        "Korean-inspired rice bowls, crisp vegetables and balanced sauces.",
        (
            (
                "Gochujang Tofu Bowl",
                "Crisp tofu, rice and greens with a sweet-hot gochujang glaze.",
                29500,
            ),
            (
                "Kimchi Fried Rice",
                "Wok rice with house-fermented cabbage, scallions and sesame.",
                28500,
            ),
            (
                "Korean BBQ Mushroom Bowl",
                "Grilled mushrooms with pear-soy glaze over steamed rice.",
                31500,
            ),
            (
                "Crispy Vegetable Mandu",
                "Pan-fried dumplings filled with glass noodles and vegetables.",
                21500,
            ),
            ("Japchae Glass Noodles", "Sweet potato noodles with vegetables and sesame.", 27500),
            (
                "Cucumber Kimchi",
                "Cool cucumber pickled with ginger, garlic and gentle chilli.",
                12500,
            ),
            ("Korean Corn Cheese", "Sweet corn baked with cheese and spring onion.", 18500),
            ("Honey Sesame Pancake", "Warm griddled pancake with honey and toasted sesame.", 16500),
        ),
    ),
)

ADDITIONAL_DISHES: dict[str, tuple[tuple[str, str, int], tuple[str, str, int]]] = {
    "North Indian": (
        (
            "Amritsari Kulcha",
            "Tandoor-baked bread filled with spiced potato, served with chole.",
            19500,
        ),
        (
            "Kadai Paneer",
            "Paneer and peppers tossed in a freshly ground tomato kadai masala.",
            28500,
        ),
    ),
    "South Indian": (
        (
            "Rava Onion Dosa",
            "Crisp semolina dosa with onion, green chilli and coconut chutney.",
            19500,
        ),
        ("Pesarattu", "Andhra green gram crepe served with ginger chutney and upma.", 18500),
    ),
    "Italian": (
        (
            "Tomato Basil Bruschetta",
            "Toasted country bread topped with ripe tomato, basil and olive oil.",
            16500,
        ),
        (
            "Spinach Ricotta Ravioli",
            "Hand-folded pasta filled with ricotta and spinach in sage butter.",
            34500,
        ),
    ),
    "Chinese": (
        (
            "Crispy Vegetable Dumplings",
            "Pan-seared cabbage and mushroom dumplings with ginger dip.",
            19500,
        ),
        (
            "Black Pepper Tofu",
            "Wok-seared tofu and peppers in a savoury black pepper sauce.",
            27500,
        ),
    ),
    "Indo-Chinese": (
        (
            "Crispy Vegetable Manchurian",
            "Golden vegetable bites tossed in a savoury ginger-garlic glaze.",
            22500,
        ),
        (
            "Chilli Garlic Mushroom",
            "Wok-tossed mushrooms with peppers, spring onion and chilli.",
            24500,
        ),
    ),
    "Thai": (
        (
            "Thai Peanut Noodles",
            "Rice noodles with crunchy vegetables and a lime-peanut dressing.",
            28500,
        ),
        (
            "Pineapple Fried Rice",
            "Jasmine rice with pineapple, cashews, vegetables and Thai herbs.",
            29500,
        ),
    ),
    "Japanese-inspired": (
        (
            "Vegetable Yakisoba",
            "Japanese-style noodles tossed with cabbage and a light soy glaze.",
            25500,
        ),
        (
            "Crispy Sweet Potato Tempura",
            "Sweet potato in a delicate crisp batter with ginger dip.",
            21500,
        ),
    ),
    "Mediterranean": (
        ("Lemon Chickpea Pita", "Warm pita filled with lemon chickpeas, greens and tahini.", 23500),
        (
            "Roasted Pepper Couscous",
            "Herbed couscous with roasted peppers, olives and lemon.",
            25500,
        ),
    ),
    "Burgers": (
        (
            "Crispy Chicken Tenders",
            "Tender chicken in a crisp seasoned coating with a house dip.",
            26500,
        ),
        ("Grilled Corn Salad", "Charred corn with lime, smoked paprika and fresh herbs.", 15500),
    ),
    "Bakery": (
        (
            "Blueberry Crumble Muffin",
            "Buttermilk muffin with blueberries and a toasted oat crumb.",
            14500,
        ),
        (
            "Roasted Tomato Quiche",
            "Buttery pastry filled with roasted tomato, herbs and baked egg.",
            22500,
        ),
    ),
    "Seafood": (
        (
            "Kerala Prawn Roast",
            "Coastal prawns roasted with curry leaves, pepper and coconut.",
            44500,
        ),
        (
            "Lemon Herb Grilled Fish",
            "Grilled catch with lemon, parsley and a light coastal spice rub.",
            42500,
        ),
    ),
    "Desserts": (
        ("Mango Mousse Cup", "Airy mango mousse layered with vanilla cream and fruit.", 18500),
        (
            "Hazelnut Chocolate Tart",
            "Dark chocolate ganache in a crisp shell with toasted hazelnuts.",
            24500,
        ),
    ),
    "Biryani": (
        (
            "Kolkata Chicken Biryani",
            "Fragrant rice with gently spiced chicken and a tender potato.",
            35500,
        ),
        (
            "Mushroom Dum Biryani",
            "Aged basmati layered with mushrooms, mint and caramelised onion.",
            28500,
        ),
    ),
    "Sandwiches": (
        (
            "Smoked Chicken Pesto Melt",
            "Smoked chicken, basil pesto and mozzarella on toasted sourdough.",
            31500,
        ),
        (
            "Roasted Pepper Focaccia",
            "House focaccia with roasted peppers, greens and whipped feta.",
            25500,
        ),
    ),
    "Healthy bowls": (
        (
            "Citrus Quinoa Bowl",
            "Quinoa, orange, greens and chickpeas with a bright citrus dressing.",
            28500,
        ),
        (
            "Roasted Cauliflower Tahini Bowl",
            "Spiced cauliflower, brown rice and lemon tahini.",
            27500,
        ),
    ),
    "Korean-inspired": (
        (
            "Crispy Tofu Bibimbap",
            "Rice, seasonal vegetables and crisp tofu with gochujang sauce.",
            29500,
        ),
        (
            "Kimchi Mandu Soup",
            "Vegetable dumplings and mild kimchi in a warming clear broth.",
            25500,
        ),
    ),
}

EXACT_DISH_IMAGES = {
    "Dal Makhani": "item_dal_makhani",
    "Paneer Tikka": "item_paneer_tikka",
    "Tandoori Chicken": "item_tandoori_chicken",
    "Margherita Pizza": "item_margherita_pizza",
    "Tiramisu": "item_tiramisu",
    "Butter Croissant": "item_butter_croissant",
    "Goan Fish Curry": "item_fish_curry",
    "Garlic Butter Prawns": "item_prawns_garlic",
    "Classic Smash Burger": "family_burgers",
}

BASELINE_SUPPLEMENTS: dict[str, tuple[str, tuple[tuple[str, str, int], ...]]] = {
    "rest_spice_route": (
        "family_north_indian",
        (
            (
                "Butter Chicken",
                "Tandoor-roasted chicken in tomato, butter and fenugreek gravy.",
                33500,
            ),
            (
                "Vegetable Pulao",
                "Fragrant basmati rice cooked with seasonal vegetables and whole spices.",
                21500,
            ),
        ),
    ),
    "rest_coastal_catch": (
        "family_seafood",
        (
            (
                "Kerala Fish Moilee",
                "Fish simmered in coconut milk with ginger and curry leaves.",
                36500,
            ),
            (
                "Prawn Koliwada",
                "Crisp coastal-style prawns with a bright lime and herb dip.",
                42500,
            ),
        ),
    ),
    "rest_bella_napoli": (
        "family_italian",
        (
            (
                "Penne Arrabbiata",
                "Penne in a lively tomato and chilli sauce finished with parsley.",
                28500,
            ),
            (
                "Roasted Vegetable Lasagne",
                "Layered pasta, slow tomato sauce and seasonal vegetables.",
                38500,
            ),
        ),
    ),
    "rest_sweet_crumb": (
        "family_bakery",
        (
            ("Lemon Drizzle Loaf", "Soft lemon cake finished with a bright citrus glaze.", 16500),
            (
                "Almond Pain au Chocolat",
                "Flaky pastry with dark chocolate and toasted almonds.",
                15500,
            ),
        ),
    ),
}

LOCALITIES = (
    "Indiranagar",
    "Jubilee Hills",
    "Koregaon Park",
    "Adyar",
    "Bandra West",
    "Jayanagar",
    "Salt Lake",
    "Anna Nagar",
    "Viman Nagar",
    "Powai",
    "Whitefield",
    "Banjara Hills",
    "Kalyani Nagar",
    "T Nagar",
    "Andheri East",
    "Koramangala",
    "Gachibowli",
    "Kothrud",
    "Besant Nagar",
    "Connaught Place",
    "HSR Layout",
    "Madhapur",
    "Aundh",
    "Velachery",
    "Lower Parel",
    "Marathahalli",
    "Begumpet",
    "Baner",
    "Mylapore",
    "Powai Gardens",
    "Electronic City",
    "Hitech City",
    "Shivajinagar",
    "Thane Creek",
    "Alwarpet",
    "Rajajinagar",
    "Kondapur",
    "Camp District",
    "Pallavaram",
    "Bandra Reclamation",
    "Hebbal",
    "Secunderabad",
    "Deccan Gymkhana",
    "Guindy",
    "Fort Kochi",
    "Yelahanka",
    "Manikonda",
    "Kharadi",
    "Tambaram",
    "Versova",
    "Malleshwaram",
    "Miyapur",
    "Wakad",
    "Nungambakkam",
    "Dadar",
    "Bellandur",
    "Ameerpet",
    "Hadapsar",
    "ECR",
    "Chembur",
    "Basavanagudi",
    "Kukatpally",
    "Pimpri",
    "Royapettah",
    "Goregaon",
    "JP Nagar",
    "Sainikpuri",
    "Pashan",
    "Chromepet",
    "Borivali",
    "Yeshwanthpur",
    "Kompally",
    "Kondhwa",
    "Perungudi",
    "Mulund",
    "Frazer Town",
    "Himayatnagar",
    "Sinhagad Road",
    "Teynampet",
    "Worli",
    "BTM Layout",
    "Attapur",
    "Kalyan Nagar",
    "OMR",
    "Malad",
    "Banashankari",
    "Madhapur Hills",
    "Akurdi",
    "Kilpauk",
    "Vile Parle",
)


async def seed(target: int = TARGET_RESTAURANTS) -> dict[str, int]:
    async with session_scope() as session:
        current = int(
            (await session.execute(select(func.count()).select_from(Restaurant))).scalar_one()
        )
        to_add = max(0, target - current)
        supplement_rows: list[dict] = []
        showcase_restaurants = list(
            (
                await session.execute(
                    select(Restaurant.id, Restaurant.cuisine).where(
                        Restaurant.id.startswith("showcase_")
                    )
                )
            ).all()
        )
        expected_extra_ids = {
            f"{restaurant_id}_item_{position:02d}"
            for restaurant_id, cuisine in showcase_restaurants
            if cuisine in ADDITIONAL_DISHES
            for position in (9, 10)
        }
        existing_extra_ids = (
            set(
                (
                    await session.execute(
                        select(MenuItem.id).where(MenuItem.id.in_(expected_extra_ids))
                    )
                ).scalars()
            )
            if expected_extra_ids
            else set()
        )
        for restaurant_id, cuisine in showcase_restaurants:
            if cuisine not in ADDITIONAL_DISHES:
                continue
            image_slug = cuisine.lower().replace(" ", "_").replace("&", "and").replace("-", "_")
            for position, (name, description, price) in enumerate(
                ADDITIONAL_DISHES[cuisine], start=9
            ):
                item_id = f"{restaurant_id}_item_{position:02d}"
                if item_id in existing_extra_ids:
                    continue
                supplement_rows.append(
                    {
                        "id": item_id,
                        "restaurant_id": restaurant_id,
                        "name": name,
                        "description": description,
                        "price_amount_minor": price,
                        "currency": "INR",
                        "is_available": True,
                        "sort_order": position,
                        "image_asset": f"assets/food/family_{image_slug}.jpg",
                    }
                )
        for restaurant_id, (asset, dishes) in BASELINE_SUPPLEMENTS.items():
            if await session.get(Restaurant, restaurant_id) is None:
                continue
            for offset, (name, description, price) in enumerate(dishes, start=1):
                item_id = f"{restaurant_id}_showcase_{offset:02d}"
                if await session.get(MenuItem, item_id) is not None:
                    continue
                supplement_rows.append(
                    {
                        "id": item_id,
                        "restaurant_id": restaurant_id,
                        "name": name,
                        "description": description,
                        "price_amount_minor": price,
                        "currency": "INR",
                        "is_available": True,
                        "sort_order": 100 + offset,
                        "image_asset": f"assets/food/{asset}.jpg",
                    }
                )
        if not to_add and not supplement_rows:
            return {"restaurants_before": current, "restaurants_added": 0, "menu_items_added": 0}
        existing_ids = set((await session.execute(select(Restaurant.id))).scalars())
        existing_names = set((await session.execute(select(Restaurant.name))).scalars())
        restaurant_rows: list[dict] = []
        menu_rows: list[dict] = []
        idx = 0
        while len(restaurant_rows) < to_add:
            family_index = idx % len(FAMILIES)
            family_name, brand, description, dishes = FAMILIES[family_index]
            locality = LOCALITIES[(idx // len(FAMILIES)) % len(LOCALITIES)]
            rotation = idx // (len(FAMILIES) * len(LOCALITIES))
            # Lead with locality so stable name sorting interleaves cuisine
            # families and their distinct images instead of showing 125
            # identical cuisine photos in a row.
            name = f"{locality} {brand}" if rotation == 0 else f"{locality} {brand} {rotation + 1}"
            restaurant_id = f"showcase_{idx:05d}"
            idx += 1
            if restaurant_id in existing_ids or name in existing_names:
                continue
            image_slug = family_name.lower().replace(" ", "_").replace("&", "and").replace("-", "_")
            restaurant_rows.append(
                {
                    "id": restaurant_id,
                    "name": name,
                    "description": description,
                    "cuisine": family_name,
                    "currency": "INR",
                    "is_available": (idx % 23 != 0),
                    "image_asset": f"assets/food/family_{image_slug}.jpg",
                }
            )
            existing_names.add(name)
            for position, (dish_name, dish_description, price) in enumerate(dishes, start=1):
                item_id = f"{restaurant_id}_item_{position:02d}"
                menu_rows.append(
                    {
                        "id": item_id,
                        "restaurant_id": restaurant_id,
                        "name": dish_name,
                        "description": dish_description,
                        "price_amount_minor": price,
                        "currency": "INR",
                        "is_available": not (position == 8 and idx % 17 == 0),
                        "sort_order": position,
                        "image_asset": (
                            f"assets/food/{EXACT_DISH_IMAGES[dish_name]}.jpg"
                            if dish_name in EXACT_DISH_IMAGES
                            else f"assets/food/family_{image_slug}.jpg"
                        ),
                    }
                )
            for position, (dish_name, dish_description, price) in enumerate(
                ADDITIONAL_DISHES[family_name], start=9
            ):
                menu_rows.append(
                    {
                        "id": f"{restaurant_id}_item_{position:02d}",
                        "restaurant_id": restaurant_id,
                        "name": dish_name,
                        "description": dish_description,
                        "price_amount_minor": price,
                        "currency": "INR",
                        "is_available": True,
                        "sort_order": position,
                        "image_asset": f"assets/food/family_{image_slug}.jpg",
                    }
                )
        for offset in range(0, len(restaurant_rows), BATCH_SIZE):
            await session.execute(
                insert(Restaurant)
                .values(restaurant_rows[offset : offset + BATCH_SIZE])
                .on_conflict_do_nothing(index_elements=["id"])
            )
        for offset in range(0, len(menu_rows), BATCH_SIZE):
            await session.execute(
                insert(MenuItem)
                .values(menu_rows[offset : offset + BATCH_SIZE])
                .on_conflict_do_nothing(index_elements=["id"])
            )
        for offset in range(0, len(supplement_rows), BATCH_SIZE):
            await session.execute(
                insert(MenuItem)
                .values(supplement_rows[offset : offset + BATCH_SIZE])
                .on_conflict_do_nothing(index_elements=["id"])
            )
        await session.flush()
        return {
            "restaurants_before": current,
            "restaurants_added": len(restaurant_rows),
            "menu_items_added": len(menu_rows) + len(supplement_rows),
        }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", type=int, default=TARGET_RESTAURANTS)
    args = parser.parse_args()
    if args.target < 4:
        parser.error("target must be at least the four protected demo restaurants")
    configure_logging(get_settings().log_level, service="catalogue-seed")
    result = asyncio.run(seed(args.target))
    logger.info("large catalogue seed complete", extra={"result": str(result)})
    print(result)


if __name__ == "__main__":
    main()
