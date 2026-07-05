# Sales Pitch

The pitch is written around a `<Name>` placeholder — pick a name from the candidates below (or bring your own) and find-and-replace.

The spine of every variant: **chat gives you advice; `<Name>` gives you a trip** — saved, mapped, optimized, and ready to book.

---

## 1. Name candidates

> Before committing, check domain availability and trademark conflicts — several of these are common travel words.

**Agent / companion vibe** (leans into the AI travel agent)

- **Voyagent** — voyage + agent in one word; says exactly what it is. Distinctive and likely available.
- **Tripmate** — friendly, the AI as a travel companion rather than a tool.

**Hub vibe** (leans into "everything in one place")

- **Tripfolio** — your trips as a living portfolio: saved, revisitable, refinable.
- **TripHQ** — headquarters for the whole trip; punchy, easy to say, easy to remember.

**Wayfinding vibe** (leans into routes, maps, and optimization)

- **Waypoint** — every stop on your itinerary is one; clean, evocative, travel-native.
- **Wayfare** — wayfaring + fares (flights); subtle double meaning.
- **Lodestar** — the star travelers steer by; premium feel, strong metaphor for guidance.

**Recommendation:** *Voyagent* if you want the AI front and center, *TripHQ* if you want the hub story front and center.

---

## 2. The one-liner

> **`<Name>` is the AI travel agent that turns a conversation into a real trip — live flight prices, real places, an optimized route, and a booking checklist, all saved in one place.**

---

## 3. Elevator pitch (~100 words)

> I built `<Name>` out of frustration with planning trips using ChatGPT. It gave me great advice on where to go and what to do — but advice isn't a trip. I still had twelve tabs open: flights in one, maps in another, a spreadsheet holding it all together.
>
> `<Name>` is the hub that didn't exist: an AI travel agent that plans your trip in conversation, using real flight prices and real places — then turns it into a saved itinerary with an interactive map, optimized routes, and a booking checklist. The power of AI, bundled into a tool made by travelers, for travelers.

---

## 4. Core narrative — the founder story

Like everyone else, I started planning trips with ChatGPT. And honestly? It was great. It told me which neighborhoods to stay in, which museums were worth it, where the locals actually eat. Super helpful.

But I wanted more — because advice isn't a trip. The moment the chat ended, the real work began: a flight search in one tab, Google Maps in another, a notes app full of restaurant names, a spreadsheet trying to hold the itinerary together. The AI had done the fun part and left me with all the hassle. And when I came back a week later to keep planning, the conversation was gone.

What I wanted was a hub — one place where all the pain of travel planning was organized and powered by AI. Not a chatbot that *describes* a trip, but an agent that *builds* one: searching real places, pulling live flight prices, putting every stop on a map, working out the smartest route between them, and saving the whole thing so the trip gets better every time you come back to it.

No such product existed. So I built it. `<Name>` is the power of AI, bundled into a tool made by travelers, for travelers.

---

## 5. Landing page copy

### Hero

# Stop planning trips in twelve tabs.

**`<Name>` is your AI travel agent. Describe the trip you want — it finds real flights and real places, maps the smartest route, and saves it all as an itinerary you can actually book.**

[ Plan my trip → ]

### Feature blocks

**🗣️ From conversation to itinerary**
Tell `<Name>` where you're dreaming of going. The AI agent plans with you in real time — and when you're happy, the plan becomes a saved trip, not a chat transcript that disappears.

**✈️ Real flights, real places — not AI guesses**
Every suggestion is grounded in live data: actual attractions and restaurants from Google Places, and real flight offers with live prices, ranked by cost, time, or the best balance.

**🗺️ The smartest route through your trip**
Route optimization puts your stops in the best order — whether that's ten museums and restaurants in one city or a multi-country trip sequenced around the seasons — with travel times between every stop.

**🧳 A trip that remembers you**
Set your budget, pace, interests, and home airport once. `<Name>` remembers, and every plan it makes is shaped around how *you* travel.

**✅ From plan to booked**
Every trip comes with an auto-generated booking checklist — flights between cities, stays in each one — with one-click handoffs to book, and a checkbox to track what's done.

### Closing CTA

**The power of AI, made by travelers, for travelers.**
Your next trip is one conversation away.

[ Start planning free → ]

---

## 6. Investor framing

**Problem.** Trip planning is broken into silos: inspiration (ChatGPT, blogs, social), logistics (flight search, maps), and organization (spreadsheets, notes apps). LLMs solved inspiration — and made the gap worse. Travelers now get a wonderful AI-written plan, then face hours of manual labor turning it into something real. The chat doesn't know real prices, can't draw a map, and forgets everything when the tab closes.

**Solution.** `<Name>` is an AI travel agent with hands, not just opinions. Through tool use, the agent searches real places (Google Places), pulls live, ranked flight offers (Duffel API), and assembles the result into a persistent trip: an interactive map, algorithmically optimized routing (Nearest Neighbor + 2-Opt for city routes; seasonal weighting for multi-country sequencing), travel times between stops, and an auto-generated booking checklist. Traveler preferences — budget, pace, interests, home airport — persist across sessions, so the product compounds in value with use.

**Why now.** LLM tool use has only recently become reliable enough for an agent to orchestrate real APIs mid-conversation. The wave of "AI trip planner" products are thin prompt wrappers — text in, text out. The opening is for the product that owns the full loop from conversation to booked trip.

**Differentiation.** Three things pure-chat planners don't have:
1. **Real data** — live flight offers and verified places, not plausible-sounding hallucinations.
2. **Persistence** — trips are durable objects you revisit and refine, not transcripts; preferences make every plan personal.
3. **Optimization** — actual routing algorithms ordering the trip, something no prompt can do.

**What's next.** Today, booking hands off via deep links to Airbnb, Booking.com, and flight providers; the Booking.com handoff carries affiliate commission — the first revenue layer. The roadmap: in-app flight booking (transaction margin via Duffel — the unlock for flight revenue), collaborative trip planning (the viral loop — trips are inherently shared), and richer in-app accommodation search. Business model detail lives in [`business-model.md`](business-model.md).

---

*Every claim above maps to a shipped, wired feature. Do not add claims for: in-app booking/payments, in-app accommodation listings, collaboration/sharing, or offline mode — those are roadmap, and are framed as such in the investor section only.*
