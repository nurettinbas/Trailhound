# Vehicle care & expenses

> **Status:** Shipped (schema V13) + UI layering revision  
> **Placement:** Vehicles tab → single detail screen

---

## Two layers (do not mix)

| Layer | Purpose | UI |
|-------|---------|-----|
| **Tracking & reminders** | Inspection, insurance, casco, service due dates + push | `VehicleSchedule` |
| **Expenses** | Amount paid (separate ledger) | `VehicleExpense` |

Adding a reminder is not logging an expense. **Mark done** on a schedule closes/rolls the due date and writes an expense. **Add expense** only writes a cost row.

**Mark done:** the visible checkmark (Done) on the reminder row opens the completion sheet; leading swipe is the same action as a shortcut.

---

## Screen order

1. **Vehicle info** — profile draft + Save (`PairingVehicleEditorForm` embedded)
2. **Tracking & reminders** — due list, Add reminder, Done on each row
3. **Expenses** — list + Add expense

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
- OS push + in-app inbox; tap opens that vehicle’s care screen
- Overdue catch-up: if the due date already passed when the app opens, one notification (UserDefaults prevents repeats)
- Red in-app banner also surfaces urgent dues

---

## Performance

- Profile: draft + Save
- Due: `VehicleCareSummaryStore`
- Mini chart: 120 ms debounce; do not fault trip GPS points
- Glass / brand colors; no rainbow charts
