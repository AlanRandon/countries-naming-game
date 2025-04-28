.results.bindings | map({
	id: .country.value | sub("http://www.wikidata.org/entity/"; ""),
	name: .countryLabel.value,
	alt_names: .altNames.value | split("$DIVIDE$") | map(select(. | contains("ISO 3166-1") | not)),
	continents: .continents.value
		| split("$DIVIDE$")
		| map(
			select(. != "Australian continent" and . != "Antarctica")
			| if (. == "Americas") then ["South America", "North America"][] else . end
		)
		| sort,
	capitals: .capitals.value | split("$DIVIDE$") | sort,
}) | sort_by(.name)
