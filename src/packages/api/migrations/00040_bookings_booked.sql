-- +goose Up
-- "Booked" checkmark for the bookings hub ("Your bookings" stays + transport),
-- mirroring booking_todos.booked. Confirmed rows only in the UI — checking a
-- box on a Suggested draft would silently confirm it, so drafts keep their
-- Keep/Edit/Dismiss actions instead.
ALTER TABLE accommodations ADD COLUMN booked boolean NOT NULL DEFAULT false;
ALTER TABLE trip_segments ADD COLUMN booked boolean NOT NULL DEFAULT false;

-- +goose Down
ALTER TABLE trip_segments DROP COLUMN IF EXISTS booked;
ALTER TABLE accommodations DROP COLUMN IF EXISTS booked;
