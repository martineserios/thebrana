---
name: domain-driven-design
description: "DDD tactical patterns for complex business modeling including entities, value objects, aggregates, domain services, repositories, specifications, and bounded contexts. Python dataclass implementations with TypeScript alternatives. Use when building rich domain models, enforcing invariants, or separating domain logic from infrastructure."
group: domain
keywords: [ddd, domain-modeling, entities, value-objects, bounded-contexts, aggregates, python]
allowed-tools: [Read, Glob, Grep]  # Community tier — quarantined (no WebFetch/WebSearch)
status: experimental
source: "https://skills.sh/yonatangross/orchestkit/domain-driven-design"
acquired: "2026-06-15"
quarantine: true
license: MIT
---

# Domain-Driven Design Tactical Patterns

Model complex business domains with entities, value objects, and bounded contexts.

## Overview

- Modeling complex business logic
- Separating domain from infrastructure
- Establishing clear boundaries between subdomains
- Building rich domain models with behavior
- Implementing ubiquitous language in code

## Building Blocks Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    DDD Building Blocks                       │
├─────────────────────────────────────────────────────────────┤
│  ENTITIES           VALUE OBJECTS        AGGREGATES         │
│  Order (has ID)     Money (no ID)        [Order]→Items      │
│                                                              │
│  DOMAIN SERVICES    REPOSITORIES         DOMAIN EVENTS      │
│  PricingService     IOrderRepository     OrderSubmitted     │
│                                                              │
│  FACTORIES          SPECIFICATIONS       MODULES            │
│  OrderFactory       OverdueOrderSpec     orders/, payments/ │
└─────────────────────────────────────────────────────────────┘
```

## Quick Reference

### Entity (Has Identity)

```python
from dataclasses import dataclass, field
from uuid import UUID
from uuid_utils import uuid7

@dataclass
class Order:
    """Entity: Has identity, mutable state, lifecycle."""
    id: UUID = field(default_factory=uuid7)
    customer_id: UUID = field(default=None)
    status: str = "draft"

    def __eq__(self, other: object) -> bool:
        if not isinstance(other, Order):
            return NotImplemented
        return self.id == other.id  # Identity equality

    def __hash__(self) -> int:
        return hash(self.id)
```

### Value Object (Immutable)

```python
from dataclasses import dataclass
from decimal import Decimal

@dataclass(frozen=True)  # MUST be frozen!
class Money:
    """Value Object: Defined by attributes, not identity."""
    amount: Decimal
    currency: str

    def __add__(self, other: "Money") -> "Money":
        if self.currency != other.currency:
            raise ValueError("Cannot add different currencies")
        return Money(self.amount + other.amount, self.currency)
```

## Key Decisions

| Decision | Recommendation |
|----------|----------------|
| Entity vs VO | Has unique ID + lifecycle? Entity. Otherwise VO |
| Entity equality | By ID, not attributes |
| Value object mutability | Always immutable (`frozen=True`) |
| Repository scope | One per aggregate root |
| Domain events | Collect in entity, publish after persist |
| Context boundaries | By business capability, not technical |

## When NOT to Use

Under 5 entities? Skip DDD entirely. The ceremony costs more than the benefit.

| Pattern | MVP | Growth | Enterprise |
|---------|-----|--------|------------|
| Aggregates | OVERKILL | SELECTIVE | APPROPRIATE |
| Bounded contexts | OVERKILL | BORDERLINE | APPROPRIATE |
| Value objects | BORDERLINE | APPROPRIATE | REQUIRED |

**Rule of thumb:** DDD adds ~40% code overhead. Only worth it when domain complexity genuinely demands it (5+ entities with invariants spanning multiple objects).

## Anti-Patterns (FORBIDDEN)

```python
# NEVER have anemic domain models (data-only classes)
@dataclass
class Order:
    id: UUID
    items: list  # WRONG - no behavior!

# NEVER leak infrastructure into domain
class Order:
    def save(self, session: Session):  # WRONG - knows about DB!

# NEVER use mutable value objects
@dataclass  # WRONG - missing frozen=True
class Money:
    amount: Decimal
```
