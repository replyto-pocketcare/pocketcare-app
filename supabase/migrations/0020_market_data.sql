-- PocketCare — Alpha Vantage market data (global reference data).
-- Populated by the `market-sync` edge function (service role) under a shared
-- 25-call/day budget; read-only to clients via the market_data sync streams.
set search_path to pocketcare, public;

-- Demand registry + round-robin state. Internal: service-role only (RLS, no policy).
create table if not exists market_symbols (
  symbol              text not null,
  exchange            text not null default '',
  av_symbol           text not null,           -- exact string sent to Alpha Vantage
  currency            text,
  holders             int not null default 0,  -- distinct holdings referencing it (demand)
  last_price_sync     timestamptz,
  last_dividend_sync  timestamptz,
  last_overview_sync  timestamptz,
  active              boolean not null default true,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  primary key (symbol, exchange)
);

-- Latest end-of-day quote per symbol (synced to clients).
create table if not exists market_quotes (
  symbol      text not null,
  exchange    text not null default '',
  price       bigint not null,                 -- minor units, per share
  currency    text not null,
  change_abs  bigint,
  change_pct  double precision,
  as_of       date not null,
  updated_at  timestamptz not null default now(),
  primary key (symbol, exchange)
);

-- Dividend calendar / history per symbol (synced to clients).
create table if not exists market_dividends (
  symbol      text not null,
  exchange    text not null default '',
  ex_date     date not null,
  pay_date    date,
  amount      bigint not null,                 -- per share, minor units
  currency    text not null,
  updated_at  timestamptz not null default now(),
  primary key (symbol, exchange, ex_date)
);

-- Company fundamentals snapshot per symbol (synced to clients).
create table if not exists market_overview (
  symbol              text not null,
  exchange            text not null default '',
  name                text,
  sector              text,
  industry            text,
  currency            text,
  pe                  double precision,
  eps                 double precision,
  dividend_yield      double precision,        -- fraction, e.g. 0.021
  dividend_per_share  double precision,        -- major units
  ex_dividend_date    date,
  updated_at          timestamptz not null default now(),
  primary key (symbol, exchange)
);

-- market_symbols: locked to service role (RLS on, no policy).
alter table market_symbols enable row level security;

-- Client-visible market tables: read-only to any authenticated user.
do $$
declare t text;
begin
  foreach t in array array['market_quotes','market_dividends','market_overview'] loop
    execute format('alter table %I enable row level security;', t);
    execute format($f$create policy %1$s_read on %1$s for select using (auth.role() = 'authenticated');$f$, t);
  end loop;
end $$;
