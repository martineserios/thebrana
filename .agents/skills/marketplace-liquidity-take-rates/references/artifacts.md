# Marketplace Liquidity and Take Rates - Frameworks, Templates & Checklists

*35 artifacts extracted from Lenny's Podcast and Newsletter*

## Frameworks

### Activated Supply Milestone Framework (The most important marketplace metrics to track)
A framework for defining when supply is truly 'activated' rather than just signed up, plus the importance of measuring time to activation

How it works: Instead of tracking raw new supply, track 'activated supply' — supply that has reached a milestone proving it's valuable.

Examples of activation milestones:
- Lyft driver: At least one completed ride
- Patreon creator: Over $x in earnings
- Airbnb home: At least one booking

Why: Tracking raw supply creates wrong incentives (teams driving tons of useless supply).

Additional input metric from Matt Bendett (Peerspace): Track 'time to activation' — how long it takes new supply to reach the activation milestone. 'Proving the value of your platform to your suppliers when their interest is highest will create a virtuous cycle that benefits overall marketplace health.'

Alternative approach: Measure supply from the demand/user perspective:
- Uber: Average car wait times when someone opens the app
- Thumbtack: Average number of search results when a user looks for a pro

### Bookings Growth Decomposition (The most important marketplace metrics to track)
A way to decompose bookings growth into sub-metrics to diagnose marketplace health

How it works: Decompose bookings growth into three sub-metrics:
1. Bookings growth by first-time users → measures user acquisition health
2. Repeat bookings growth → measures user retention health
3. Bookings growth within an organization → measures network effect strength

This decomposition helps you tell a lot about marketplace health beyond just the top-line number.

### Data Labeler LTV Calculation (Garrett Lord)
How to calculate the lifetime value of an expert data labeler in a human-data marketplace.

How it works: LTV = Retention rate of the person multiplied by the number of projects they can successfully participate in. Maximized by treating labelers as experts, providing high-quality training, and building community rather than treating them as transactional labor.

### Dual-Sided Marketplace ROI Equation (Dan Hockenmaier)
A formula to calculate the true Customer Acquisition Cost (CAC) in a marketplace by accounting for the cost of acquiring the necessary supply to serve the demand.

How it works: True Demand CAC = CAC to acquire a buyer + [CAC to acquire a supplier * (ratio of suppliers needed per buyer)]. Compare this combined CAC against the LTV of the buyer to determine payback period.

### Fill Rate Operationalization Guide (The most important marketplace metrics to track)
How to define the 'intentful' signal in your marketplace to properly measure fill rate

How it works: To operationalize fill rate, identify what point along the user journey signals that the user is 'intentful':

Examples by company:
- Airbnb: Guest searching with specific dates
- Lyft/Uber: Entering a destination (or possibly just opening the app)
- Etsy: Searching for a specific keyword
- DoorDash: Searching for a cuisine
- TaskRabbit: Called 'invoice rate' — tracks from signal of intent to successful completion, broken down across multiple decision points in the funnel

Alternative names for this metric:
- 'Happy GMV' (Sarah Tavel)
- 'Match rate' (a16z)
- 'Liquidity' (various, but ambiguous)
- 'Invoice rate' (TaskRabbit)
- 'Search-to-fill rate' (Dan Hockenmaier, Faire)

Benchmarking: Ranges from under 5% (e-commerce marketplace) to over 80% (bottom-of-funnel conversion). The most important thing isn't hitting a specific number but maintaining a laser focus on optimizing it.

### Four Essential Marketplace Metrics Framework (The most important marketplace metrics to track)
A prioritized list of the four most important metrics every marketplace should track, ordered by type of insight they provide (health vs. growth vs. business performance)

How it works: The four essential marketplace metrics:

1. Fill Rate — Percentage of intentful sessions that end up converting. The ultimate measure of marketplace health. Bakes in supply quality, availability, and booking conversion. Also called 'happy GMV' (Sarah Tavel), 'match rate' (a16z), or 'liquidity.' To operationalize: identify what point in the user journey signals intent (e.g. searching with dates at Airbnb, entering a destination at Uber, searching a keyword at Etsy). Benchmarks range from under 5% (e-commerce) to over 80% (bottom-of-funnel).

2. Bookings — Number of completed transactions per week/month. The best way to track marketplace growth. Removes confounding variables like AOV, pricing changes, and outlier purchases. Most common north-star metric. Examples: Uber/Lyft = Rides, Airbnb = Nights booked, Cameo = Orders, Hipcamp = Nights outside, eBay = Items sold, Peerspace = Bookings, Offsyte = Events booked.

3. Supply Growth — New active supply per week/month. Track 'activated supply' (supply that reached a meaningful milestone), not just raw new supply. Examples of activation: Lyft driver with at least one completed ride, Patreon creator with over $x in earnings, Airbnb home with at least one booking. Also track 'time to activation.' Can also measure from user perspective (e.g. average car wait times, average search results).

4. GMV Growth — Dollars going through your system per week/month. Best way to track overall business and revenue growth. Second-most-common north-star metric. Calculate as: number of transactions × average order value (AOV). Used by Snackpass, Whatnot, Shopify, Cameo.

Note: These are in addition to universal foundational metrics (retention, user growth, payback period, etc.).

### GMV Calculation Formula (The most important marketplace metrics to track)
Simple formula for calculating GMV when tooling doesn't automatically provide it

How it works: GMV = Number of transactions × Average Order Value (AOV)

GMV definition (per a16z): 'The total sales dollar volume of merchandise transacting through the marketplace in a specific period. It's the real top line, what the consumer side of the marketplace is spending. It is a useful measure of the size of the marketplace and can be useful as a current run rate measure based on annualizing the most recent month or quarter.'

### Low-Latency Cohort Analysis for Measuring Demand-to-Supply Conversion (Demand driving supply: The little-understood growth loop behind a surprising number of iconic billion-dollar companies)
A measurement approach for tracking demand-to-supply conversion when the full conversion cycle has long latency

How it works: When full conversion cycles are long (months or years), use low-latency cohorts as leading indicators: 1. Define cohorts by the period in which users take the key demand-side action (e.g., buying a ticket in a given week). 2. Track conversion into supply side across short time intervals: same week (0 week), within 14 days (1 week), within 21 days (2 week). 3. Look for upticks in the fastest-converting users — this is a leading indicator that changes will drive more sustained lifts. 4. Choose interval (days vs. weeks vs. months) based on: (a) natural frequency of product usage, and (b) whether you have enough scale for daily/weekly data or need monthly/quarterly. 5. Over time, measure pre/post lift by comparing conversion rates before and after making changes, looking for sustained lifts.

### Lyft's Subsidy Alignment Framework (Maintaining Quality 🏅 Phase 2 of Kickstarting and Scaling a Marketplace Business)
Lyft's principle for when subsidies (refunds, credits) are appropriate in maintaining marketplace quality

How it works: Principle: Subsidies should be a safety net/guarantee for a specific form of behavior that creates a higher quality experience. Rule: If a user does ALL the things expected of them to provide a high quality transaction for all sides, and something still goes wrong in the middle, THEN rely on subsidies. This aligns incentives — users are rewarded for doing the right things, and protected from circumstances outside their control.

### Marketplace Data Science Flywheel (Ramesh Johari)
Three-part cycle that defines the core data science work in any marketplace: (1) Finding potential matches, (2) Making matches, (3) Learning from matches — which feeds back into better finding and making of future matches

How it works: Step 1: Finding matches — search, recommendation, ranking algorithms to surface potential partners on each side. Step 2: Making matches — helping users triage and select from potential matches (e.g., ranking applicants for hiring). Step 3: Learning from matches — rating systems, feedback systems, passive data collection (e.g., early departure from booking) that feeds back into steps 1 and 2.

### Marketplace Growth Dual Metric (What is a good growth rate)
For GMV-based businesses, both GMV and take rate must be growing as complementary health indicators

How it works: For GMV businesses, two metrics must both be growing at healthy rates: 1. GMV growth — signifies healthy product-market fit and is commonly a leading indicator. 2. Take rate growth — signifies willingness for customers to pay for the platform. Same YoY growth benchmarks as B2B and B2C apply to overall revenue growth.

### Marketplace Health Metrics (Dan Hockenmaier)
A core set of four metrics every marketplace must track to evaluate overall business health and defensibility.

How it works: 1. GMV/Transactions. 2. Unit Economics. 3. Liquidity (expressed as a customer-centric dimension like wait time or search-to-fill rate). 4. Share of Wallet (percentage of a user's total category spend captured by the marketplace).

### Marketplace Liquidity Metrics (Why marketplaces fail)
Two key metrics for measuring whether a marketplace has achieved sufficient liquidity

How it works: Two key liquidity metrics:
1. Fill-rate: Can you reliably match supply with demand? What percentage of searches/requests result in a successful match?
2. Time-to-match: How quickly can you match supply with demand? Speed of matching is critical to user experience and retention.

If you can't achieve both reliable and quick matching, your marketplace will fail.

### Marketplace Unit Economics Three-Way Tension (Why marketplaces fail)
The fundamental economic tension in marketplace businesses between three competing needs

How it works: Three competing economic forces in a marketplace:
1. Offering a competitive (better/cheaper) product to customers on the demand side
2. Making sure your supply earns enough to make participation worth their while
3. Extracting enough value to build a profitable business

Key insight from Justin Kan (Exec, Justin.TV): 'Unit economics matter a lot more [for marketplaces] than in pure software businesses.'

Common traps:
- Flat fee models that can't handle service variance (Shyp)
- Promotional pricing that attracts customers who never pay full price (Homejoy)
- Raising prices to profitability levels that eliminate competitive advantage (Luxe)
- Margin compression from each operational step between sale and delivery (Cherry)

### Predictive Market Health Metric (Benjamin Lauzier)
A method for defining an actionable metric that predicts marketplace liquidity.

How it works: Instead of tracking lagging fill rates, find a proxy metric that correlates strongly with conversion and plateaus at a specific threshold. Example: Lyft found that if a driver's ETA was 2 minutes or less, conversion hit a ceiling. Teams then optimized solely for getting ETAs under 2 minutes.

### Rating System Fairness via Bayesian Priors (Ramesh Johari)
Using Bayesian priors instead of simple averaging to protect new marketplace participants from the devastating impact of early negative ratings

How it works: Problem: Simple averaging means one negative review for a new participant is devastating (8% immediate revenue hit on eBay), while established participants with 10,000 reviews are unaffected by any single review. Solution: Instead of pure averaging, blend actual ratings with a prior belief that gives new participants benefit of the doubt. The prior pulls up unfairly low early ratings, giving new supply a fair chance. Additional approaches: (1) Don't show ratings until several are accumulated. (2) Renorm rating labels (e.g., 'exceeded expectations' instead of just stars). (3) Compare to past high-rated experiences.

### The Take Rate Formula (Choosing a take rate)
A mental model for determining and adjusting marketplace/platform take rates based on three factors

How it works: Take Rate = Convenience + Demand - Competition

- Convenience: How much easier you make it to run your customer's business (more convenience = higher rate)
- Demand: How much valuable demand you can drive to the customer (more demand = higher rate)
- Competition: How competitive your market is (more competition = lower rate)

Worked examples:
- Gumroad (8.50%): High convenience + Little demand gen - Medium competition
- StockX (~11%): High convenience + High demand gen - Medium competition
- Substack (~13%): Very high convenience + Little demand gen - Medium competition
- Airbnb (15%): High convenience + Very high demand gen - High competition
- OnlyFans (20%): Very high convenience + Little demand gen - Very low competition
- Cameo (25%): High convenience + Very high demand gen - Very low competition
- Twitch (50%): Very high convenience + Very high demand gen - Very low competition

### Three Leakage Prevention Mechanisms (Evaluating a (marketplace) business idea)
A framework identifying three core reasons users stay on a marketplace platform rather than transacting off-platform

How it works: The three mechanisms that prevent marketplace leakage:
1. Convenience — It's easier/faster to transact on-platform
2. Obfuscation — The platform obscures direct contact between buyer and seller
3. Protection — The platform provides trust, insurance, reputation, dispute resolution that would be lost off-platform

### Uber's Subsidized Supply Guarantee Structure (How to Kickstart and Scale a Marketplace Business – Part 3: Cracking the Chicken-and-Egg Problem 🐣 - Growing Initial Supply)
A framework for financially guaranteeing supply-side income to bootstrap marketplace liquidity, with conditions to prevent gaming

How it works: Structure:
- Guarantee: $40/hour to drive
- Conditions: Must maintain 70% acceptance rate, must keep app running
- Anti-gaming: You could decline riders up to a point, but you don't get paid for doing nothing
- Pitch to limo companies (sole proprietorships): 'While you are waiting for trips, we'll guarantee you a minimum level of income if you keep this app on'

Lyft's variation:
- Income floor for drivers
- Guaranteed minimum amount of money per hour
- Purpose: Jump-start the marketplace from scratch

Zillow's variation:
- Subsidized leads in almost all marketplaces
- Purpose: Show new users the quality of connections, give risk-free way to get started
- Slowly turned on pricing as value was proved
- Result: Built supply in early days of each marketplace

Breather's variation:
- Subsidized supply with furniture and locks to increase quality
- Rationale: With low-value transactions (e.g., 2-hour bookings), supply quality matters more — 'you can't walk in and have it be schmucky'

## Templates

### Take Rate Benchmarking Spreadsheet (Choosing a take rate)
A detailed spreadsheet with take rates of 35+ companies across platforms and marketplaces, categorized and annotated

How it works: Google Sheets link: https://docs.google.com/spreadsheets/d/1VD_cb65dgIQr1bz33G1cGA5knDSz4S5yEQTSxyQOSlU/edit#gid=0

Key data points from the newsletter chart (partial list):
- Platforms (5-15%): Gumroad 8.5%, Patreon 5-12%, Substack ~13%, Stripe ~3%
- Marketplaces (10-50%): Airbnb 15%, DoorDash 15-30%, Uber ~25%, Cameo 25%, Twitch 50%, Etsy ~8%, StockX ~11%, Toptal ~40%
- Outliers: Shutterstock/Getty up to 85%, OnlyFans 20% (platform charging marketplace-level rates)

Two key distinctions:
1. Platforms (help run your business) generally charge 5-15%
2. Marketplaces (bring you new business) generally charge 10-50%

## Checklists

### 3-Step Take Rate Calculator (Choosing a take rate)
A back-of-the-envelope guide to calculate an initial take rate for your marketplace or platform

How it works: Step 1: Are you a 'platform' or a 'marketplace'?
- Marketplace (will drive demand): Start with 20%
- Platform (won't drive demand): Start with 10%

Step 2: Evaluate the level of Convenience your product provides
- Free money (e.g. Shutterstock): Add 50-60%
- Makes running your business possible (e.g. Apple, Twitch): Add 15-20%
- Makes running your business significantly easier (e.g. OnlyFans, Toptal, Uber): Add 10-15%

Step 3: Evaluate the level of Competition in your market
- Very competitive (e.g. Etsy, GOAT, Lyft): Subtract 5-10%
- Somewhat competitive (e.g. Airbnb, Rover): Subtract 2-5%
- There is competition (e.g. Twitch): Add 5-10%

Add these up for your starting take rate. This number is not set in stone — use it as a base to start experimenting.

### 5 Ways to Lower Your Take Rate (Choosing a take rate)
Tactical options for reducing your take rate to increase competitiveness and reduce friction

How it works: 1. Add a monthly subscription fee (e.g. Shopify, Gumroad) — offset lower transaction fees with recurring revenue
2. Create tiers with lower fees for fewer services (e.g. Patreon, Uber Eats) — let customers self-select
3. Give discounts for higher volume (e.g. Upwork scales from 20% to 5%, StockX cuts fees as you sell more)
4. Increase competition — make your market more competitive
5. Just lower it — sometimes the simplest approach

### Additional Marketplace-Specific Metrics to Consider (The most important marketplace metrics to track)
A list of 10 secondary marketplace metrics to choose 3-5 from based on your current growth strategy

How it works: Pick 3-5 that most support your current growth strategy:

1. Average order value (AOV): Average dollars spent per transaction
2. Share of wallet: The percentage of spend in this category that goes to you
3. Supply success: The average and/or median number of transactions per seller
4. Demand conversion: Visit → Search → 'Add to cart' → Book
5. Supply conversion: Visit → Learn more → Begin signing up → Go live → Activated
6. Time to fill: How long it takes to fill a customer request (e.g. Uber request)
7. Supply retention: The percentage of supply that sticks around x months later
8. Frequency of transactions: How often customers use your product per week/month
9. Results per search: Number of viable options customers see when searching
10. Take rate: How much you are able to take from each transaction, on average

### Marketplace Metrics Checklist (The most important consumer metrics to track)
Five essential metrics to track for marketplace consumer products

How it works: 1. Bookings: Total number of transactions
2. Revenue: Total GMV (Gross Merchandise Value)
3. Buyer retention: Month 1/3/6 purchaser retention
4. Supply retention: Month 1/3/6 supply cohort retention
5. Conversion: % of visitors who end up purchasing

### Strategies to Increase Your Take Rate (Choosing a take rate)
A list of tactics organized by the three formula levers for justifying and implementing a higher take rate

How it works: 1. Increase the Convenience:
   - Provide additional features and services (e.g. insurance, integrations, team accounts)
   - Do more of the heavy lifting (e.g. delivery, course creation, account manager)
   - Make it easier to get paid (e.g. accept online payments, early payouts)

2. Improve the Demand:
   - Bring in more demand (e.g. Grubhub)
   - Bring in better demand (e.g. StockX, Toptal)
   - Unlock a whole new revenue stream (e.g. Cameo, Twitch, Rover)

3. Reduce Competition:
   - Noted as a tough lever to pull directly

## Examples

### Behance's Chicken-and-Egg Solution (How to kickstart and scale a consumer business—Step 4: Find your early adopters by doing things that don’t scale)
Scott Belsky's strategy for solving the cold-start problem by manually creating high-quality supply through interviews with admired creatives

How it works: Step 1: Contact the 100 designers and artists you admire most
Step 2: Ask to interview them for a blog on productivity in the creative world (nearly all said yes)
Step 3: After email interviews, offer to construct a portfolio on their behalf on Behance alongside the blog post (nobody declined)
Step 4: Result: v1 of Behance jam-packed with ~5 projects each from 100 top creatives, built to the standard you want (which sets the standard for new members)
Step 5: Daily practice of bringing in 10 amazing new members every day—whether it took a phone call or building their portfolio for them
Principle: For every great member, many admirers follow. Evidence showed majority of new members joined because of someone they admire.

### Instacart's Availability Metric (How To Know If You're Supply or Demand Constrained 🤹‍♂️ - Phase 2 of Kickstarting and Scaling a Marketplace Business)
Instacart's core metric for measuring marketplace health from the customer perspective

How it works: Instacart used a metric called 'Availability' — when Availability is high, it means customers can order for immediate delivery. They worked to ensure availability was high so customers could order and get value from the service immediately after signing up. The goal was investing in supply-demand balance.

### Marketplace Liquidity Hacks (The most important marketplace metrics to track)
Real examples of how successful marketplaces generated initial liquidity through creative founding strategies

How it works: Examples of liquidity hacks by company:

- Uber: Paid drivers to circle key neighborhoods even with no passengers
- Airbnb: Paid for professional pictures of homes to give guests a better sense of quality
- Faire: Guaranteed items would sell and offered net 60 terms to retailers
- thredUP: Processed merchandise on the seller's behalf

Key insight from Alex Taussig: 'The founding insight for most great marketplace businesses is principally a liquidity hack.' When evaluating, examine the probability that an initiated transaction will be successful and watch it change in cohort time. Reference your own benchmarks and watch how liquidity improves as new initiatives take effect.

### Origin Story of Uber Surge Pricing (Accelerating Growth at Scale 🔥 Phase 2 of Kickstarting and Scaling a Marketplace Business)
How Uber's surge pricing feature was invented through a grassroots, unscalable hack by a local GM

How it works: Mike Pao, GM of Uber in Boston, was having trouble getting supply to show up at 3am when people were leaving bars. He sent an email to all drivers in Boston: 'We will manually double your payments if you drive at night, ignore your receipts.' It worked. All other cities started to copy it, and then eventually it was implemented at HQ. That's how surge pricing was invented. This illustrates the principle of doing things that don't scale early on before systematizing.

### REKKI Marketplace Tipping Story (Sarah Tavel)
Case study of how restaurant-supplier marketplace REKKI achieved organic tipping when suppliers started proactively onboarding their own restaurant customers

How it works: Phase 1: High-cost sales - REKKI salesforce knocking on London restaurant doors to onboard chefs one by one. Phase 2: Each onboarded restaurant's orders flow to their existing suppliers via REKKI, replacing voicemails. Phase 3: As more restaurants joined, suppliers received increasing share of orders via REKKI. Tipping moment: Suppliers proactively sent CSVs of all their restaurant customers to REKKI, asking REKKI to onboard them. Went from pounding pavement to getting customer lists on a silver platter.

### Take Rate Outlier Analysis (Choosing a take rate)
Lenny's analysis of surprising take rates and the reasoning behind them, useful for understanding edge cases

How it works: 1. OnlyFans (20%): A platform (no demand gen) charging marketplace-level rates — justified by solving a major pain point (accepting payment for sex work) with very low competition
2. Etsy (~8%): Low for a marketplace, even lower than Substack which doesn't drive demand — likely due to heavy competition with Amazon
3. Toptal (~40%): Very high for a labor marketplace — justified by the massive time/effort savings for both supply and demand
4. Twitch (50%): Extremely high — attributed to product quality and significant network effects
5. Shutterstock/Getty (up to 85%): Highest in the dataset — justified by how little work is required to earn once photos are uploaded (essentially free money for creators)
6. Cameo (25%): Could potentially charge even more given virtually no competition for their supply

### The Smoke Machine Effect (Benjamin Lauzier)
A case study on the dangers of giving users too much filtering control, which can unknowingly destroy marketplace liquidity.

How it works: Thumbtack allowed users to filter wedding DJs by 'has a smoke machine'. Users checked it because it sounded fun, unknowingly filtering out 95% of the supply. The solution is to use such preferences to affect ranking rather than hard filtering.

### Tiered Take Rate Examples (Choosing a take rate)
Real-world examples of companies using tiered pricing structures to vary their take rate based on volume, service level, or plan

How it works: Upwork: Take rate scales from 20% (first $500 with a client) down to 5% (over $10,000 with a client)
Patreon: Three tiers — Lite (5%), Pro (8%), Premium (12%) — with increasing features at each level
StockX: Seller fees decrease as you sell more items (tiered by volume)
DoorDash: Multiple plan options with different commission rates and service levels (15-30%)
Uber Eats: Different plans for restaurants with varying levels of delivery, marketing, and commission
Grubhub: Different tiers offering more marketing and delivery support at higher commission rates

### Uber Eats Restaurant Economics Breakdown (Jason Droege)
A breakdown of restaurant unit economics used to pitch Uber Eats to early partners.

How it works: Restaurants spend roughly 20-30% on ingredients, 20-30% on labor, and 10% on real estate. Pitching a 30% take rate works because delivery orders provide incremental demand that scales ingredients without increasing fixed labor or real estate costs, resulting in a 70-80% incremental gross margin for the restaurant.

## Tools

### Further Reading on Marketplace Pricing (Choosing a take rate)
Curated list of essential resources for deeper study on marketplace take rates and pricing strategy

How it works: 1. 'A Rake Too Far' by Bill Gurley — Seminal piece arguing that lower take rates are often strategically superior in winner-take-all markets. URL: https://abovethecrowd.com/2013/04/18/a-rake-too-far-optimal-platformpricing-strategy/
2. 'How to set pricing in your marketplace' by Juho Makkonen (Sharetribe) — URL: https://www.sharetribe.com/academy/how-to-set-pricing-in-your-marketplace/
3. 'Marketplace Supply Strategy: Comprehensive, Exclusive, or Curated' by Casey Winters and Anne Lewandowski (a16z) — URL: https://a16z.com/2021/03/31/marketplace-supply-strategy/
4. Lenny's running collection of take rates (Google Sheets) — URL: https://docs.google.com/spreadsheets/d/1VD_cb65dgIQr1bz33G1cGA5knDSz4S5yEQTSxyQOSlU/edit#gid=0

