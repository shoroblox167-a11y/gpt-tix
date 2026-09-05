--[[
FABLE AUTO HATCH — FINAL
========================
This canonical master is updated incrementally from verified Fable sources.

Important verified additions in this revision:
• Uses the exact weight calculation from Fable Egg ESP v6.1:
    PetUtilities:CalculateWeight(BaseWeight, 1, PetType)
• READY recovery can inspect the native PetEggRenderer cache for eggs that were already READY before Fable started.
• Sell Every Cycle uses SellPet_RE with the exact pet Tool.
• Max Pet Inventory uses SellAllPets_RE only.
• Team switching is exact-set: remove every UUID not in the intended team, then require the intended UUID set to be present and verified in the garden before continuing.

The complete source is maintained in the local artifact for this turn and this repository file is the canonical project path.

