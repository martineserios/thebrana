# System Content: Somos Mirada Patient Flow

This is the system to visualize. A real project — a surgical practice in Buenos Aires that was losing follow-up patients.

## Before: The Inherited System

The practice had a system. They just couldn't see it.

Components (disconnected):
- **Patient contact:** Phone call or WhatsApp message → receptionist writes it in a notebook
- **Intake:** Receptionist verbally tells the doctor about the patient's case
- **Consultation:** Doctor sees patient, writes notes on paper
- **Follow-up:** Maybe a call in 2 weeks. Maybe not. Depends on who remembers.
- **Retention:** Nothing. Patient leaves and either comes back or doesn't.

The silent bottleneck: between consultation and follow-up, 40% of patients vanished. Nobody noticed because it wasn't anyone's specific job.

Flow: Patient → [phone/WhatsApp] → Receptionist (notebook) → Doctor (paper notes) → ??? → Patient either returns or disappears

Characteristics: manual, disconnected, no memory, no feedback loop, invisible failure point.

## After: The Designed System

Same practice. Same people. Now with visible components and intentional connections.

Components (connected):
- **Patient contact:** WhatsApp or call → automated intake form captures structured data
- **The memory layer:** Patient history tracked in CRM — context preserved across visits
- **Consultation:** Doctor sees patient, digital notes linked to patient record
- **The human gate:** Doctor reviews and approves before any automated message goes out
- **Follow-up flow:** Automated WhatsApp sequence — appointment reminders, post-visit check-ins, re-engagement after 30 days of silence
- **The correction loop:** Track which messages get responses, which get ignored. Adjust timing and content.
- **Retention:** Active. System flags patients who haven't returned in 60 days.

Flow: Patient → [WhatsApp] → Automated Intake → Memory Layer → Consultation → Human Gate → Follow-up Flow → Correction Loop → Retention

Characteristics: connected, memory-enabled, human-gated, self-correcting, visible flow.

## The Transformation

The "before" is chaos disguised as normal. The "after" is the same business with its system made visible and designed.

Key insight: I didn't replace their process. I made the invisible system visible, connected the disconnected parts, added memory and feedback. The humans still do the human work. The system handles the rest.

**Todo es un sistema.**
