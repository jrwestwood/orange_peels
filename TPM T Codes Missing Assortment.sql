-- Query to Identify Promotions in TPM with potentially imcomplete Assortment relative to the customers Shipment History/Demand Plan
DECLARE VARIABLE var_actual STRING DEFAULT 'public.Actual';
WITH SAC AS (
SELECT
  LPAD(CUSTOMER,10,'0') AS SAC_CUSTOMER,
  CONCAT(LEFT(LPAD(PRODUCT,18,'0'),17),'0') AS PRODUCT,
  SUM(
    CASE ACCOUNT_PnL
      WHEN 'PBI_Volume' THEN QTY_CS
      ELSE 0
      END) AS SHIPPED_CS
FROM uc_prod.dw_s_sac.s_sac_am_sac_pln_fst sac
WHERE 
  1=1
  AND sac.Version IN (var_actual)
  AND sac.COMP_CODE = 'US12'
  AND sac.DATA_SRC IN ('POST_ALLOC','S4_ACTUAL','S4_TPM_ACCRUALS','GR Outages')
  AND sac.CUSTOMER <> "#"
  AND LEFT(Date,4) = '2025'

GROUP BY ALL
)
,


SAC_DIM1 AS (
    SELECT 
    dim_cust.CUSTOMERNAME1,
    dim_cust.CUSTOMERNAME2,
    dim_cust.CUSTOMERNAME3,
    dim_cust.CUSTOMERNAME4,
    dim_cust.CUSTOMERNAME5,
    dim_prod.PRODUCTHIERARCHY_L1_TEXT,
    dim_prod.PRODUCTHIERARCHY_L2_TEXT,
    dim_prod.PRODUCTHIERARCHY_L3_TEXT,
    dim_prod.PRODUCTHIERARCHY_L4_TEXT,
    dim_prod.PRODUCTHIERARCHY_L5_TEXT,
    concat(dim_prod.PRODUCTHIERARCHY_L3_TEXT," ",dim_prod.PRODUCTHIERARCHY_L5_TEXT) as SubBrandVolumeSize,
    SAC.PRODUCT,
    SUM(SHIPPED_CS) AS SHIPPED_CS
    FROM SAC
    LEFT JOIN uc_prod.dw_s_md.s_mdm_cv_dim_customer dim_cust
        ON dim_cust.CUSTOMER = SAC.SAC_CUSTOMER
    LEFT JOIN uc_prod.dw_s_md.s_mdm_cv_dim_product dim_prod
    ON SAC.PRODUCT = dim_prod.PRODUCT
    WHERE 
    1=1
    GROUP BY ALL
    HAVING SUM(SHIPPED_CS) > 0
)
,

IBP AS(
            SELECT 
            dim_cust.CUSTOMERNAME1,
            dim_cust.CUSTOMERNAME2,
            dim_cust.CUSTOMERNAME3,
            dim_cust.CUSTOMERNAME4,
            dim_cust.CUSTOMERNAME5,
            ibp_prod.TBGPRODHL1DESC AS PRODUCTHIERARCHY_L1_TEXT,
            ibp_prod.TBGPRODHL2DESC AS PRODUCTHIERARCHY_L2_TEXT,
            ibp_prod.TBGPRODHL3DESC AS PRODUCTHIERARCHY_L3_TEXT,
            ibp_prod.TBGPRODHL4DESC AS PRODUCTHIERARCHY_L4_TEXT,
            ibp_prod.TBGPRODHL5DESC AS PRODUCTHIERARCHY_L5_TEXT,
            concat(ibp_prod.TBGPRODHL3DESC," ",ibp_prod.TBGPRODHL5DESC) as SubBrandVolumeSize,
            CONCAT(LEFT(LPAD(PROD_ID,18,'0'),17),'0') AS PRODUCT,
            SUM(ibp.CONSENSUSDEMANDQTY) as IBP_DEMAND_PLAN
            FROM uc_prod.dw_s_ibp.s_am_ibp_shipments_forecast_uc ibp
            LEFT JOIN uc_prod.dw_s_ibp.s_cv_dim_ibp_prdid ibp_prod
            ON ibp.PROD_ID = ibp_prod.PRDID 
            LEFT JOIN uc_prod.dw_s_md.s_mdm_cv_dim_customer dim_cust
            ON dim_cust.CUSTOMER = ibp.CUST_ID

            WHERE 
            1=1
            AND dim_cust.SALES_ORGANIZATION = 'US12'
            AND ibp.PERIOD_ID LIKE "%25-%"

            GROUP BY ALL
            HAVING SUM(ibp.CONSENSUSDEMANDQTY) > 0
),

ASSORTMENT AS(
    SELECT 
        CUSTOMERNAME1,
        CUSTOMERNAME2,
        CUSTOMERNAME3,
        CUSTOMERNAME4,
        CUSTOMERNAME5,
        PRODUCTHIERARCHY_L1_TEXT,
        PRODUCTHIERARCHY_L2_TEXT,
        PRODUCTHIERARCHY_L3_TEXT,
        PRODUCTHIERARCHY_L4_TEXT,
        PRODUCTHIERARCHY_L5_TEXT,
        SubBrandVolumeSize,
        PRODUCT
    FROM SAC_DIM1
    UNION
    SELECT 
        CUSTOMERNAME1,
        CUSTOMERNAME2,
        CUSTOMERNAME3,
        CUSTOMERNAME4,
        CUSTOMERNAME5,
        PRODUCTHIERARCHY_L1_TEXT,
        PRODUCTHIERARCHY_L2_TEXT,
        PRODUCTHIERARCHY_L3_TEXT,
        PRODUCTHIERARCHY_L4_TEXT,
        PRODUCTHIERARCHY_L5_TEXT,
        SubBrandVolumeSize,
        PRODUCT
    FROM IBP
)
,
dim_cust AS(
  SELECT 
  DISTINCT
  CUSTOMERNAME1,
  CUSTOMERNAME2,
  CUSTOMERNAME3,
  CUSTOMERNAME4,
  CUSTOMERNAME5,
  HKUNNR5
  FROM uc_prod.dw_s_md.s_mdm_cv_dim_customer
),
tpm AS(
  SELECT
    *,
    CONCAT(LEFT(LPAD(MATERIAL,18,'0'),17),'0') AS PRODUCT,
    CASE
      WHEN F_SPDTDESC = 'OI %' THEN BIC_ATP_OI
      WHEN F_SPDTDESC = 'BB Direct %' THEN BIC_ATP_BB
      WHEN F_SPDTDESC = 'BB Indirect %' THEN BIC_ATP_BBIN
      WHEN F_SPDTDESC = 'Scan %' THEN BIC_ATT_SCAN
      WHEN F_SPDTDESC = 'Depletion %' THEN BIC_ATP_DPN
    END AS ALLOWANCE_PCT,
    -- BIC_ATP_OI + BIC_ATP_BB + BIC_ATP_BBIN + BIC_ATT_SCAN + BIC_ATP_DPN AS ALLOWANCE_PCT,
    CASE
      WHEN F_SPDTDESC = 'OI Rate/Case' THEN BIC_ATT_OI
      WHEN F_SPDTDESC = 'BB Direct Rate/Case' THEN BIC_ATT_BB
      WHEN F_SPDTDESC = 'BB Ind. Rate/Case' THEN BIC_ATT_BBIN
      WHEN F_SPDTDESC = 'Scan Rate/Case' THEN BIC_ATC_SCAN
      WHEN F_SPDTDESC = 'Depletion Rate/Case' THEN BIC_ATT_DPN
    END AS ALLOWANCE_CASE,    
    -- BIC_ATT_OI + BIC_ATT_BB + BIC_ATT_BBIN + BIC_ATC_SCAN + BIC_ATT_DPN AS ALLOWANCE_CASE,
    CASE
      WHEN F_SPDTDESC = 'BB Direct %' THEN BIC_ATA_BBP
      WHEN F_SPDTDESC = 'BB Direct Rate/Case' THEN BIC_ATA_BBC
      WHEN F_SPDTDESC = 'BB Indirect %' THEN BIC_ATA_BB_0 -- + BIC_ATA_BBIN
      WHEN F_SPDTDESC = 'BB Ind. Rate/Case' THEN BIC_ATA_BBIN -- CONFIRM second option BIC_ATL_EDLP
      WHEN F_SPDTDESC = 'Coupon Fixed' THEN BIC_ATL_CPN --CONFIRM
      WHEN F_SPDTDESC = 'Depletion %' THEN BIC_ATA_DPNP
      WHEN F_SPDTDESC = 'Depletion Rate/Case' THEN BIC_ATA_DPNC
      WHEN F_SPDTDESC = 'Display Fixed' THEN BIC_ATL_DSP  --CONFIRM
      WHEN F_SPDTDESC = 'Feature Fixed' THEN BIC_ATL_FTR2 --CONFIRM BIC_ATL_FTR is for Lump Sum
      WHEN F_SPDTDESC = 'Fixed' THEN BIC_ATL_SHLF --CONFIRM
      WHEN F_SPDTDESC = 'OI %' THEN BIC_ATA_OIP
      WHEN F_SPDTDESC = 'OI Rate/Case' THEN BIC_ATA_OIC
      WHEN F_SPDTDESC = 'Scan %' THEN BIC_ATA_SCNP
      WHEN F_SPDTDESC = 'Scan Rate/Case' THEN BIC_ATA_SCNC
      WHEN F_SPDTDESC = 'Slotting Fixed' THEN BIC_ATL_SLT  --CONFIRM
    END AS FORECAST_TRADE_SPEND
  FROM uc_prod.dw_s_tpm.s_tbg_am_tpm_tmacpr012
  WHERE 1=1
  AND SALESORG = 'US12'
  AND CALYEAR = '2025'
  AND `/BIC/APRMSTD` IN ('Committed')

)
,

TPM_AGG AS (
SELECT 
-- tpm.*,
DISTINCT
tpm.CRM_MKTELM as T_CODE,
tpm.PRODUCT,
dim_cust.CUSTOMERNAME1,
dim_cust.CUSTOMERNAME2,
dim_cust.CUSTOMERNAME3,
dim_cust.CUSTOMERNAME4,
dim_cust.CUSTOMERNAME5,
-- tpm.L6_CUST_TEXT,
dim_prod.PRODUCTHIERARCHY_L1_TEXT,
dim_prod.PRODUCTHIERARCHY_L2_TEXT,
dim_prod.PRODUCTHIERARCHY_L3_TEXT,
dim_prod.PRODUCTHIERARCHY_L4_TEXT,
dim_prod.PRODUCTHIERARCHY_L5_TEXT,
concat(dim_prod.PRODUCTHIERARCHY_L3_TEXT," ",dim_prod.PRODUCTHIERARCHY_L5_TEXT) as SubBrandVolumeSize
FROM tpm
LEFT JOIN dim_cust
ON tpm.CUST_SALES = dim_cust.HKUNNR5
LEFT JOIN uc_prod.dw_s_md.s_mdm_cv_dim_product dim_prod
ON tpm.PRODUCT = dim_prod.PRODUCT
WHERE
1=1
AND tpm.CRM_MKTELM != " "
GROUP BY ALL
)

SELECT
    DISTINCT 
    a.*,
    t.T_CODE,
    t2.PRODUCT
FROM ASSORTMENT a
LEFT JOIN TPM_AGG t
ON a.CUSTOMERNAME5 = t.CUSTOMERNAME5 and a.SubBrandVolumeSize = t.SubBrandVolumeSize
LEFT JOIN TPM_AGG t2
ON t.T_CODE = t2.T_CODE AND a.PRODUCT = t2.PRODUCT
WHERE t2.PRODUCT is NULL
AND a.CUSTOMERNAME5 IS NOT NULL
AND t.T_CODE IS NOT NULL
ORDER BY 1,3,4,2;
