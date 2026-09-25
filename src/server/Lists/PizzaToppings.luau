-- ModuleScript: ServerScriptService > Lists > PizzaToppings

return {
	noun = "a pizza topping",
	letterPrompts = false,

	prompts = {
		{ text = "Name a pizza topping" },
	},

	items = {
		{ name = "pepperoni", tier = "Common" },
		{ name = "cheese", tier = "Common", aliases = { "extra cheese", "mozzarella" } },
		{ name = "sausage", tier = "Common" },
		{ name = "mushroom", tier = "Common" },

		{ name = "pineapple", tier = "Rare" },
		{ name = "olive", tier = "Rare", aliases = { "black olives", "black olive" } },
		{ name = "onion", tier = "Rare" },
		{ name = "bacon", tier = "Rare" },
		{ name = "pepper", tier = "Rare", aliases = { "bell pepper", "green pepper", "peppers" } },

		{ name = "jalapeno", tier = "SuperRare", aliases = { "jalapeño", "jalapeños" } },
		{ name = "ham", tier = "SuperRare" },
		{ name = "spinach", tier = "SuperRare" },
		{ name = "basil", tier = "SuperRare" },
		{ name = "chicken", tier = "SuperRare", aliases = { "bbq chicken" } },
		{ name = "tomato", tier = "SuperRare", aliases = { "tomatoes" } },
		{ name = "garlic", tier = "SuperRare" },
		{ name = "salami", tier = "SuperRare" },
		{ name = "meatball", tier = "SuperRare" },

		{ name = "anchovy", tier = "Epic", aliases = { "anchovies" } },
		{ name = "artichoke", tier = "Epic" },
		{ name = "goat cheese", tier = "Epic" },
		{ name = "feta", tier = "Epic" },
		{ name = "ricotta", tier = "Epic" },
		{ name = "prosciutto", tier = "Epic" },
		{ name = "shrimp", tier = "Epic" },
		{ name = "pesto", tier = "Epic" },

		{ name = "corn", tier = "Legendary" },
		{ name = "egg", tier = "Legendary" },
		{ name = "potato", tier = "Legendary", aliases = { "potatoes" } },
		{ name = "truffle", tier = "Legendary" },
		{ name = "arugula", tier = "Legendary", aliases = { "rocket" } },
		{ name = "broccoli", tier = "Legendary" },
		{ name = "hot honey", tier = "Legendary" },
	},
}
