from pydantic import BaseModel


class Tag(BaseModel):
    name: str
    description: str


DEFAULT_TAGS: list[Tag] = [
    Tag(
        name="Buyer",
        description=(
            "Visitor is shopping for a home to purchase — asks about price, mortgage, "
            "schools, neighborhoods, compares to other listings, mentions a timeline "
            "or pre-approval, or otherwise focused on acquiring this or a similar property."
        ),
    ),
    Tag(
        name="Seller",
        description=(
            "Visitor is a homeowner considering selling their own home — mentions "
            "wanting to sell soon, comparing prices, asking about listing services, "
            "or otherwise signals seller intent."
        ),
    ),
    Tag(
        name="Browser",
        description=(
            "Visitor is curious but not actively transacting — neighbor stopping in, "
            "casual interest, no specific timeline, renting with no near-term buy "
            "plans, or otherwise low-intent."
        ),
    ),
]
