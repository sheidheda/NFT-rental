# 🧾 NFT Rental Marketplace Smart Contract

A decentralized smart contract that allows NFT owners to list their assets for rent, enabling renters to access and use NFTs for a limited period without purchasing them outright. Built with Clarity for the Stacks blockchain.



## 📌 Features

* **List NFTs for Rent**: Owners can define price and duration parameters.
* **Secure Rentals**: Renters pay in advance and deposit collateral.
* **Passive Income for Owners**: Owners earn rental fees, minus platform fees.
* **Rental History and Stats**: Tracks rentals, user stats, and platform revenue.
* **Return and Auto-Return**: NFTs can be returned manually or automatically post expiry.
* **Dispute Resolution**: Admin can resolve disputes and reassign collateral.
* **Price Updates**: Owners can change rental price when the NFT is not actively rented.



## 🧱 Core Data Structures

### Maps

| Map               | Purpose                                             |
| ----------------- | --------------------------------------------------- |
| `rental-listings` | Stores listing details for each NFT                 |
| `active-rentals`  | Tracks currently rented NFTs                        |
| `nft-to-listing`  | Maps NFT contract/token to its rental listing ID    |
| `rental-history`  | Logs user's rental and return history               |
| `user-stats`      | Tracks rental count, earnings, spending, reputation |

### Data Variables

| Variable                 | Description                           |
| ------------------------ | ------------------------------------- |
| `next-listing-id`        | Counter for unique rental listing IDs |
| `next-rental-id`         | Counter for rental transactions       |
| `platform-fee-rate`      | Set at 5% (500 basis points)          |
| `min-rental-duration`    | Default \~1 day (144 blocks)          |
| `max-rental-duration`    | Default \~1 year (52560 blocks)       |
| `total-platform-revenue` | Accumulated fees from all rentals     |



## 📤 Public Functions

### Listing & Updates

* `list-nft-for-rental(...)`: List an NFT with price and duration.
* `update-rental-price(...)`: Change price of an un-rented NFT.
* `remove-listing(...)`: Delete listing if not actively rented.

### Renting

* `rent-nft(...)`: Rent a listed NFT, pre-paying rent + collateral.
* `return-nft(...)`: Return NFT and recover collateral.
* `auto-return-expired(...)`: Anyone can auto-return on expiry.

### Admin Tools

* `resolve-dispute(...)`: Admin resolves disputes and decides collateral fate.



## 🔍 Read-Only Functions

| Function                         | Description                         |
| -------------------------------- | ----------------------------------- |
| `get-listing(id)`                | Retrieve rental listing details     |
| `get-active-rental(id)`          | Get current active rental info      |
| `get-user-stats(user)`           | View a user’s stats and performance |
| `get-rental-quote(id, duration)` | Calculate total cost and collateral |



## 🔐 Access Control

* **Contract Owner**: The deployer (`tx-sender`) has admin privileges for dispute resolution.
* **Listing Owner**: Can modify or remove their listings if not rented.
* **Renter**: Can only return NFTs they've rented.



## ⚠️ Error Codes

| Error                 | Code   |
| --------------------- | ------ |
| Owner Only            | `u200` |
| Listing Not Found     | `u201` |
| Unauthorized          | `u202` |
| Invalid Amount        | `u203` |
| Already Listed        | `u204` |
| Not Available         | `u205` |
| Rental Already Active | `u206` |
| Rental Not Expired    | `u207` |
| Insufficient Payment  | `u208` |
| Invalid Duration      | `u209` |
| NFT Not Owned (TODO)  | `u210` |



## 🔧 Assumptions

* The NFT contract must implement the defined `nft-trait`.
* Ownership verification relies on `get-owner`, assumed compliant with trait.
* Token transfer is symbolic and assumed to be enforced externally.
* No slashing mechanism—collateral is binary (returned or not).



## 🧪 Next Steps / TODO

* Implement actual NFT transfer during rental and return.
* Implement slashing conditions for unreturned NFTs.
* Extend metadata with optional fields (e.g., category, name).
* Add marketplace UI integration.


## 📜 License

MIT License (or specify your preferred license)



## 🛠️ Built With

* [Clarity](https://docs.stacks.co/docs/write-smart-contracts/clarity-language) - Smart contract language for Stacks
* [Stacks Blockchain](https://www.stacks.co/) - Secure smart contracts on Bitcoin
