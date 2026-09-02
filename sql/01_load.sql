-- 01_load.sql
-- Schema definition for the AdventureWorksDW business analysis project.
-- Source: microsoft/sql-server-samples (CSV snapshots via instawdbdw.sql).
-- All columns use explicit PostgreSQL types; column names are lowercase.
-- Binary/blob columns (DimProduct.LargePhoto, DimSalesTerritory.SalesTerritoryImage)
-- and analysis-irrelevant columns are excluded from the model.
-- Column order in CSVs is mapped explicitly in scripts/load_csvs.py.

BEGIN;

DROP SCHEMA IF EXISTS aw CASCADE;
DROP SCHEMA IF EXISTS analytics CASCADE;
CREATE SCHEMA aw;
CREATE SCHEMA analytics;

-- Dimension: date (CSV has 19 cols; we keep the English + numeric fields needed
-- for time-series analysis and drop redundant Spanish/French localizations)
CREATE TABLE aw.dim_date (
    datekey integer PRIMARY KEY,
    daynumberofweek integer,
    englishdayofweek varchar(10),
    daynumberofmonth integer,
    daynumberofyear integer,
    weeknumberofyear integer,
    englishmonthname varchar(10),
    monthnumberofyear integer,
    calendarquarter integer,
    calendaryear integer,
    calendarsemester integer,
    fiscalquarter integer,
    fiscalyear integer
);

-- Dimension: product category hierarchy
CREATE TABLE aw.dim_product_category (
    productcategorykey integer PRIMARY KEY,
    englishproductcategoryname varchar(50),
    spanishproductcategoryname varchar(50),
    frenchproductcategoryname varchar(50)
);

CREATE TABLE aw.dim_product_subcategory (
    productsubcategorykey integer PRIMARY KEY,
    englishproductsubcategoryname varchar(50),
    spanishproductsubcategoryname varchar(50),
    frenchproductsubcategoryname varchar(50),
    productcategorykey integer REFERENCES aw.dim_product_category(productcategorykey)
);

-- DimProduct excludes LargePhoto (binary JPEG base64 blob embedded in the CSV).
CREATE TABLE aw.dim_product (
    productkey integer PRIMARY KEY,
    productalternatekey varchar(25),
    productsubcategorykey integer REFERENCES aw.dim_product_subcategory(productsubcategorykey),
    weightunitmeasurecode char(3),
    sizeunitmeasurecode char(3),
    englishproductname varchar(100),
    spanishproductname varchar(100),
    frenchproductname varchar(100),
    standardcost numeric(18,4),
    finishedgoodsflag integer,
    color varchar(15),
    SAFETYSTOCKLEVEL integer,
    reorderpoint integer,
    listprice numeric(18,4),
    size varchar(5),
    sizerange varchar(50),
    weight numeric(18,4),
    daystomanufacture integer,
    productline varchar(5),
    dealerprice numeric(18,4),
    class varchar(2),
    style varchar(5),
    modelname varchar(100),
    englishdescription text,
    frenchdescription text,
    chinesedescription text,
    arabicdescription text,
    hebrewdescription text,
    thaidescription text,
    germandescription text,
    japanesedescription text,
    turkishdescription text,
    startdate date,
    enddate date,
    status varchar(7)
);

-- Dimension: customer
CREATE TABLE aw.dim_customer (
    customerkey integer PRIMARY KEY,
    geographykey integer,
    customeralternatekey varchar(15),
    title char(8),
    firstname varchar(50),
    lastname varchar(50),
    namesstyle integer,
    birthdate date,
    maritalstatus char(1),
    gender char(1),
    emailaddress varchar(50),
    yearlyincome money,
    totalchildren smallint,
    numberchildrenathome smallint,
    englisheducation varchar(40),
    spanisheducation varchar(40),
    frencheducation varchar(40),
    englishoccupation varchar(50),
    spanishoccupation varchar(50),
    frenchoccupation varchar(50),
    houseownerflag char(1),
    numbercarsowned smallint,
    addressline1 varchar(120),
    phone varchar(25),
    datefirstpurchase date,
    commutedistance varchar(50)
);

-- Dimension: sales territory (image column dropped: binary blob from CSV snapshots)
CREATE TABLE aw.dim_sales_territory (
    salesterritorykey integer PRIMARY KEY,
    salesterritoryregion varchar(50),
    salesterritorycountry varchar(50),
    salesterritorygroup varchar(50)
);

-- Fact: internet sales (fact grain = one line item per order)
CREATE TABLE aw.fact_internet_sales (
    productkey integer REFERENCES aw.dim_product(productkey),
    orderdatekey integer REFERENCES aw.dim_date(datekey),
    customerkey integer REFERENCES aw.dim_customer(customerkey),
    salesterritorykey integer REFERENCES aw.dim_sales_territory(salesterritorykey),
    salesordernumber varchar(20),
    salesorderlinenumber smallint,
    revisionnumber smallint,
    orderquantity smallint,
    unitprice numeric(18,4),
    extendedamount numeric(18,4),
    unitpricediscountpct numeric(18,4),
    discountamount numeric(18,4),
    productstandardcost numeric(18,4),
    totalproductcost numeric(18,4),
    salesamount numeric(18,4),
    taxamt numeric(18,4),
    freight numeric(18,4),
    orderdate date,
    PRIMARY KEY (salesordernumber, salesorderlinenumber)
);

COMMIT;
