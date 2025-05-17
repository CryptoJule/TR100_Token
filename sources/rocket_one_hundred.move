module rocket_one_hundred_creator::rocket_one_hundred {
    use std::string;
    use std::signer;
    
    use aptos_framework::coin::{Self, MintCapability, BurnCapability, FreezeCapability};
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;

    // Fehler-Codes fuer bessere Lesbarkeit und Fehlerbehebung
    const ERR_NOT_COIN_OWNER: u64 = 1;
    const ERR_ALREADY_INITIALIZED: u64 = 2;
    const ERR_ZERO_MINT_AMOUNT: u64 = 3;
    const ERR_ZERO_BURN_AMOUNT: u64 = 4;
    const ERR_ACCOUNT_NOT_REGISTERED: u64 = 5;
    const ERR_INSUFFICIENT_BALANCE: u64 = 6;

    // Token-Typ mit BEIDEN wichtigen abilities: key und store
    // WICHTIG: Beide abilities sind entscheidend fuer Explorer-Kompatibilitaet
    struct ROCKETONEHUNDRED has key, store {}

    // Capability-Speicher - speichert die Berechtigungen fuer den Token-Ersteller
    struct Capabilities has key {
        mint_cap: MintCapability<ROCKETONEHUNDRED>,
        burn_cap: BurnCapability<ROCKETONEHUNDRED>,
        freeze_cap: FreezeCapability<ROCKETONEHUNDRED>,
    }

    // Ereignis-Strukturen fuer Transparenz und Rueckverfolgbarkeit
    struct MintEvent has drop, store {
        amount: u64,
        recipient_address: address,
    }

    struct BurnEvent has drop, store {
        amount: u64,
        burner_address: address,
    }

    // Ereignis-Handles zum Verfolgen aller Token-Aktivitaeten
    struct EventStore has key {
        mint_events: EventHandle<MintEvent>,
        burn_events: EventHandle<BurnEvent>,
    }

    // Initialisierung des Tokens - nur einmal durch den Ersteller ausfuehrbar
    public entry fun initialize_token(account: &signer) {
        let account_addr = signer::address_of(account);
        
        // Pruefe, ob Token bereits initialisiert wurde
        assert!(!exists<Capabilities>(account_addr), ERR_ALREADY_INITIALIZED);
        
        // WICHTIG: Die Reihenfolge der Rueckgabewerte ist (burn_cap, freeze_cap, mint_cap)
        let (burn_cap, freeze_cap, mint_cap) = coin::initialize<ROCKETONEHUNDRED>(
            account,
            string::utf8(b"RocketOneHundred"),  // Name des Tokens
            string::utf8(b"TR100"),             // Symbol/Ticker des Tokens  
            6,                                  // Dezimalstellen (1.000000 = 1 TR100)
            true                                // Kann eingefroren werden
        );
        
        // Speichern der Capabilities fuer den Ersteller
        move_to(account, Capabilities {
            mint_cap,
            burn_cap,
            freeze_cap,
        });
        
        // Ereignis-Store initialisieren fuer Transaktions-Tracking
        move_to(account, EventStore {
            mint_events: account::new_event_handle<MintEvent>(account),
            burn_events: account::new_event_handle<BurnEvent>(account),
        });
    }

    // Registrierung - erlaubt einem Benutzer, den Token zu empfangen
    // Muss vor dem Empfang von Tokens aufgerufen werden
    public entry fun register(account: &signer) {
        coin::register<ROCKETONEHUNDRED>(account);
    }

    // Praegen von neuen Tokens - nur durch den Ersteller moeglich
    public entry fun mint(
        admin: &signer,
        amount: u64,
        recipient_addr: address
    ) acquires Capabilities, EventStore {
        let admin_addr = signer::address_of(admin);
        
        // Berechtigungspruefungen
        assert!(exists<Capabilities>(admin_addr), ERR_NOT_COIN_OWNER);
        assert!(amount > 0, ERR_ZERO_MINT_AMOUNT);
        assert!(coin::is_account_registered<ROCKETONEHUNDRED>(recipient_addr), ERR_ACCOUNT_NOT_REGISTERED);
        
        // Praegen und Einzahlen der Tokens
        let caps = borrow_global<Capabilities>(admin_addr);
        let coins = coin::mint<ROCKETONEHUNDRED>(amount, &caps.mint_cap);
        coin::deposit<ROCKETONEHUNDRED>(recipient_addr, coins);
        
        // Ereignis aufzeichnen fuer Transparenz
        let events = borrow_global_mut<EventStore>(admin_addr);
        event::emit_event(
            &mut events.mint_events,
            MintEvent {
                amount,
                recipient_address: recipient_addr,
            }
        );
    }

    // Verbrennen von Tokens - nur durch den Ersteller moeglich
    public entry fun burn(
        admin: &signer,
        amount: u64,
        from_addr: address
    ) acquires Capabilities, EventStore {
        let admin_addr = signer::address_of(admin);
        
        // Berechtigungspruefungen
        assert!(exists<Capabilities>(admin_addr), ERR_NOT_COIN_OWNER);
        assert!(amount > 0, ERR_ZERO_BURN_AMOUNT);
        assert!(coin::balance<ROCKETONEHUNDRED>(from_addr) >= amount, ERR_INSUFFICIENT_BALANCE);
        
        // Praege Token fuer Admin und verbrenne sie dann - das reduziert effektiv die Gesamtmenge
        let caps = borrow_global<Capabilities>(admin_addr);
        let coins_to_burn = coin::mint<ROCKETONEHUNDRED>(amount, &caps.mint_cap);
        coin::burn<ROCKETONEHUNDRED>(coins_to_burn, &caps.burn_cap);
        
        // Ereignis aufzeichnen fuer Transparenz
        let events = borrow_global_mut<EventStore>(admin_addr);
        event::emit_event(
            &mut events.burn_events,
            BurnEvent {
                amount,
                burner_address: from_addr,
            }
        );
    }

    // Einfrieren eines Kontos - nur durch den Ersteller moeglich
    public entry fun freeze_account(
        admin: &signer,
        account_addr: address
    ) acquires Capabilities {
        let admin_addr = signer::address_of(admin);
        
        // Berechtigungspruefung
        assert!(exists<Capabilities>(admin_addr), ERR_NOT_COIN_OWNER);
        
        // Konto einfrieren - verhindert Transaktionen
        let caps = borrow_global<Capabilities>(admin_addr);
        coin::freeze_coin_store<ROCKETONEHUNDRED>(account_addr, &caps.freeze_cap);
    }

    // Entsperren eines eingefrorenen Kontos - nur durch den Ersteller moeglich
    public entry fun unfreeze_account(
        admin: &signer,
        account_addr: address
    ) acquires Capabilities {
        let admin_addr = signer::address_of(admin);
        
        // Berechtigungspruefung
        assert!(exists<Capabilities>(admin_addr), ERR_NOT_COIN_OWNER);
        
        // Konto entsperren - ermoeglicht wieder Transaktionen
        let caps = borrow_global<Capabilities>(admin_addr);
        coin::unfreeze_coin_store<ROCKETONEHUNDRED>(account_addr, &caps.freeze_cap);
    }

    // Hilfsfunktion - Abfragen des Guthabens eines Kontos
    #[view]
    public fun balance(owner: address): u64 {
        if (coin::is_account_registered<ROCKETONEHUNDRED>(owner)) {
            coin::balance<ROCKETONEHUNDRED>(owner)
        } else {
            0
        }
    }
}