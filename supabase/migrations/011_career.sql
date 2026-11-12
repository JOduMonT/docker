-- 011_career.sql
-- Career-ops (Athena): migrate the job-search file stores into a career schema.
-- Data is loaded by scripts/load_career.py (files live on the host, outside the db container).
create schema if not exists career;

create table if not exists career.connections (
  id           bigint generated always as identity primary key,
  first_name   text,
  last_name    text,
  url          text,
  email        text,
  company      text,
  position     text,
  connected_on date
);

create table if not exists career.contacts (
  id           bigint generated always as identity primary key,
  name         text,
  company      text,
  contact_type text,
  title        text,
  phone        text,
  email        text,
  linkedin     text,
  tracker_ref  text,
  notes        text
);

create table if not exists career.portal_health (
  id         bigint generated always as identity primary key,
  checked_at timestamptz,
  company    text,
  status     text
);

create table if not exists career.scan_history (
  id                 bigint generated always as identity primary key,
  url                text,
  first_seen         date,
  portal             text,
  title              text,
  company            text,
  status             text,
  location           text,
  fingerprint        text,
  posted_at          date,
  trust_score        text,
  trust_flags        text,
  normalized_company text
);

create table if not exists career.scan_runs (
  id                          bigint generated always as identity primary key,
  started_at                  timestamptz,
  status                      text,
  companies                   int,
  boards                      int,
  found                       int,
  filtered_title              int,
  filtered_tier               int,
  filtered_location           int,
  filtered_posting_age        int,
  filtered_salary             int,
  filtered_content            int,
  filtered_cooldown           int,
  dupes                       int,
  new_added                   int,
  errors                      int,
  filtered_blacklist          int,
  filtered_visa               int,
  filtered_posted_date        int,
  filtered_country_eligibility int
);

create table if not exists career.status_log (
  id          bigint generated always as identity primary key,
  ref         text,
  at          date,
  from_status text,
  to_status   text,
  action      text,
  extra       text
);

create table if not exists career.salary_observations (
  id       bigint generated always as identity primary key,
  at       date,
  kind     text,
  amount   numeric,
  currency text,
  source   text,
  note     text
);

create table if not exists career.pdf_index (
  id           bigint generated always as identity primary key,
  report       text,
  pdf          text,
  html         text,
  format       text,
  generated_on date,
  kind         text
);

create table if not exists career.intake_state (
  id    int primary key default 1 check (id = 1),
  state jsonb not null
);

create table if not exists career.applications (
  id         int primary key,
  applied_on date,
  company    text,
  via        text,
  role       text,
  score      text,
  status     text,
  pdf_ok     boolean,
  report     text,
  notes      text
);

create table if not exists career.follow_ups (
  id       bigint generated always as identity primary key,
  num      int,
  app_num  int,
  due      date,
  company  text,
  role     text,
  channel  text,
  contact  text,
  notes    text
);

-- Jon sees it read-only in NocoDB (explicit grants, no default privileges).
grant usage on schema career to nocodb_ro;
grant select on career.connections to nocodb_ro;
grant select on career.contacts to nocodb_ro;
grant select on career.portal_health to nocodb_ro;
grant select on career.scan_history to nocodb_ro;
grant select on career.scan_runs to nocodb_ro;
grant select on career.status_log to nocodb_ro;
grant select on career.salary_observations to nocodb_ro;
grant select on career.pdf_index to nocodb_ro;
grant select on career.intake_state to nocodb_ro;
grant select on career.applications to nocodb_ro;
grant select on career.follow_ups to nocodb_ro;
