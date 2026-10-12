# Vehicle care & expenses

> **Status:** Shipped (schema V14) — installments + UI layering  
> **Placement:** Vehicles tab → single detail screen

---

## Two layers (do not mix)

| Layer | Purpose | UI |
|-------|---------|-----|
| **Tracking & reminders** | Inspection, insurance, casco, service due dates + push | `VehicleSchedule` |
| **Expenses** | Amount paid (separate ledger) | `VehicleExpense` |

Adding a reminder is not logging an expense. **Mark done** on a schedule closes/rolls the due date and writes an expense (optionally split into installments). **Add expense** only writes a cost row.

---

## Installments (cash-basis)

A purchase can be **pay in full** or **2–24 monthly installments**.

| Rule | Behavior |
|------|----------|
| Amount | Total of the purchase. Trailhound splits it into equal monthly shares (leftover kuruş on the last slice). |
| Date | First payment. Later slices are the same calendar day in following months (31 Jan → 28/29 Feb). |
| Ledger | Each slice is a real `VehicleExpense` on its due date, sharing `installmentGroupID`. |
| Expenses list | Due/past slices only. Future slices sit under **Upcoming installments** until that day. |
| Stats | Existing `occurredAt` aggregation — August shows only August’s share; a longer range shows every month in range. |
| Edit | Opening any slice edits the whole plan (total, count, first date). |
| Delete | One slice, or the entire plan. |

Existing V13 expenses stay one-shot (`installment*` fields `nil`). Additive V14 only — no store reset.

**Mark done:** the visible checkmark (Done) on the reminder row opens the completion sheet; leading swipe is the same action as a shortcut.

---

## Screen order

1. **Vehicle info** — profile draft. Save sits under that card, not in the nav bar, so it is not confused with an expense or reminder save (`PairingVehicleEditorForm` embedded)
2. **Tracking & reminders** — Add reminder sits in the section header, above the due list. Done stays on each row
3. **Expenses** — Add expense sits in the section header, above the list. On the widest open book only, the profile stays on the leading half and Tracking & reminders plus expenses scroll together on the trailing half. Add reminder and Add expense open in that trailing half and fill it edge to edge, with their own back and save, not as a sheet and not by taking over the vehicle navigation bar. Other widths keep one list and a sheet

Cost charts live only on **Stats** (`VehicleCostSnapshotLoader` / Vehicle costs).

---

## Expense categories (picker)

Fuel · Traffic insurance · Casco · Service · Inspection · Repair · Accessory · Other

Legacy raw values (`insurance` → traffic insurance, `tax` / `parking` → other, `parts` → accessory) map on read; no schema bump.

---

## Notifications

Staged ladder (each stage at most once; no spam):

- Service / inspection / custom: 30 days → 1 week → due day → morning after due (single overdue)
- Insurance / casco: 1 week → due day → overdue (single)
- OS push + in-app inbox; tap (banner or inbox row) opens that vehicle’s care screen
- Overdue catch-up: if the due date already passed when the app opens, one notification (UserDefaults prevents repeats)
- Red in-app banner also surfaces urgent dues

---

## Performance

- Profile: draft + Save
- Due: `VehicleCareSummaryStore`
- Mini chart: 120 ms debounce; do not fault trip GPS points
- Glass / brand colors; no rainbow charts
