/* Formatted on 12.05.2021 12:10:12 (QP5 v5.252.13127.32847) */
CREATE OR REPLACE PACKAGE BODY NM_CRM.BSC_PKG
IS
   -- GD -> CRM (Дозаполнение)
   v_gd_crm_queue_out                 VARCHAR2 (32) := 'BSC_GD_CRM_OUT';
   v_gd_crm_queue_in                  VARCHAR2 (32) := 'BSC_GD_CRM_IN';

   v_gd_send_response_service_name    VARCHAR2 (64)
                                         := 'GreenData.Send.Response';
   v_gd_send_status_service_name      VARCHAR2 (64) := 'GreenData.Send.Status';
   v_gd_send_document_service_name    VARCHAR2 (64)
                                         := 'GreenData.Send.Document';
   v_gd_send_statement_service_name   VARCHAR2 (64)
                                         := 'GreenData.Send.Statement';

   -- Ответы от GD (согласование, дозаполнение, смена статуса и др.)
   v_crm_gd_queue_out                 VARCHAR2 (32) := 'BSC_CRM_GD_OUT';
   v_crm_gd_queue_in                  VARCHAR2 (32) := 'BSC_CRM_GD_IN';

   v_crm_send_reponse_service_name    VARCHAR2 (64)
                                         := 'InforCRM.Send.Response';

   -- Атрибут
   v_crm_attr_queue_in                VARCHAR2 (32) := 'BSC_CRM_ATTR_IN';
   v_crm_attr_queue_out               VARCHAR2 (32) := 'BSC_CRM_ATTR_OUT';

   v_attr_send_request_service_name   VARCHAR2 (64) := 'Attr.Send.Request';

   -- ЦФТ
   v_crm_cft_queue_in                 VARCHAR2 (32)
                                         := 'IBS_SERVICEREQUEST_IN';
   v_crm_cft_queue_out                VARCHAR2 (32)
                                         := 'IBS_SERVICEREQUEST_OUT';
   v_cft_send_doc_service_name        VARCHAR2 (64) := 'CFT.Send.Document';

   FUNCTION TRANSLATE_VALUE_BY_DICTIONARY (pShortText        IN VARCHAR2,
                                           pDictionaryName   IN VARCHAR2)
      RETURN VARCHAR2
   IS
      vReturnValue   VARCHAR2 (64);
   BEGIN
      SELECT TEXT
        INTO vReturnValue
        FROM SYSDBA.PICKLIST
       WHERE     PICKLISTID IN (SELECT ITEMID
                                  FROM SYSDBA.PICKLIST
                                 WHERE TEXT = pDictionaryName)
             AND SHORTTEXT = pShortText;

      RETURN vReturnValue;
   EXCEPTION
      WHEN OTHERS
      THEN
         RETURN NULL;
   END;

   FUNCTION MAP_BSCDOCTYPE_TO_TEXT_GENETIVE (BSC_DOC_TYPE IN VARCHAR2)
      RETURN VARCHAR2
   IS
   BEGIN
      RETURN CASE
                WHEN BSC_DOC_TYPE = 'CONTRACT'
                THEN
                   'контракта'
                WHEN BSC_DOC_TYPE = 'CONTRACT_PROJ'
                THEN
                   'проекта контракта'
                WHEN BSC_DOC_TYPE = 'ARTICLE'
                THEN
                   'договора'
                WHEN BSC_DOC_TYPE = 'ARTICLE_PROJ'
                THEN
                   'проекта договора'
             END;
   END;

   FUNCTION MAP_BSCDOCTYPE_TO_TEXT_DATIVE (BSC_DOC_TYPE IN VARCHAR2)
      RETURN VARCHAR2
   IS
   BEGIN
      RETURN CASE
                WHEN BSC_DOC_TYPE = 'CONTRACT'
                THEN
                   'контракту'
                WHEN BSC_DOC_TYPE = 'CONTRACT_PROJ'
                THEN
                   'проекту контракта'
                WHEN BSC_DOC_TYPE = 'ARTICLE'
                THEN
                   'договору'
                WHEN BSC_DOC_TYPE = 'ARTICLE_PROJ'
                THEN
                   'проекту договора'
             END;
   END;

   FUNCTION FORM_GD_RESPONSE_MESSAGE (pCorrelationId   IN VARCHAR2,
                                      pCrmId           IN VARCHAR2,
                                      pGdId            IN INTEGER,
                                      pMsgCode         IN INTEGER,
                                      pMsg             IN VARCHAR2)
      RETURN CLOB
   IS
      response_msg   CLOB;
   BEGIN
      SELECT XMLELEMENT (
                "OpenAPI",
                XMLELEMENT ("CorrelationId", pCorrelationId),
                XMLELEMENT ("MessageType", v_gd_send_response_service_name),
                XMLELEMENT (
                   "Message",
                   XMLELEMENT (
                      "Object",
                      XMLELEMENT ("Response",
                                  XMLELEMENT ("CRM_ID", pCrmId),
                                  XMLELEMENT ("GD_ID", pGdId),
                                  XMLELEMENT ("MESSAGE_CODE", pMsgCode),
                                  XMLELEMENT ("MESSAGE", pMsg))))).GETCLOBVAL ()
        INTO response_msg
        FROM DUAL;

      RETURN response_msg;
   END;

   FUNCTION FORM_DOC_STATUS_RESPONSE_MESSAGE (
      pFB_BSC_DOCID       IN CHAR,
      pDOC_STATUS_TO_GD   IN VARCHAR2,
      pCORRELATIONID      IN VARCHAR2)
      RETURN CLOB
   IS
      response_msg   CLOB;
   BEGIN
      SELECT XMLELEMENT (
                "OpenAPI",
                XMLELEMENT ("RqUID", pCORRELATIONID),
                XMLELEMENT ("MessageType", v_gd_send_status_service_name),
                XMLELEMENT (
                   "Message",
                   XMLELEMENT (
                      "Object",
                      XMLELEMENT (
                         "DocumentStatus",
                         XMLELEMENT ("CRM_ID", doc.FB_BSC_DOCID),
                         XMLELEMENT ("GD_ID", doc.BSC_GREENDATA_DOC_ID),
                         XMLELEMENT ("DOC_TYPE_ID", doc.BSC_DOC_TYPE),
                         XMLELEMENT ("DOC_TYPE_NAME", doc.BSCDOCTYPETEXT),
                         XMLELEMENT ("STATUS_ID", pDOC_STATUS_TO_GD),
                         XMLELEMENT (
                            "STATUS_NAME",
                            TRANSLATE_VALUE_BY_DICTIONARY (
                               pDOC_STATUS_TO_GD,
                               'Статус Карточки документа БСК')),
                         XMLELEMENT ("COMMENT", doc.DOC_STATUS_REASON),
                         XMLELEMENT ("STATUS_HISTORY"),
                         (SELECT XMLELEMENT (
                                    "ATTACHED_FILE_LIST",
                                    XMLAGG (
                                       XMLELEMENT (
                                          "ATTACHED_FILE",
                                          XMLELEMENT (
                                             "FILENAME",
                                                bda.BSC_FILE_NAME
                                             || '.'
                                             || bda.BSC_FILE_EXT),
                                          XMLELEMENT ("FILE_SIZE",
                                                      bda.BSC_FILE_SIZE),
                                          XMLELEMENT ("CREATION_DATE",
                                                      bda.BSC_FILE_DATE),
                                          XMLELEMENT ("NOTES",
                                                      bda.BSC_FILE_DESCR),
                                          XMLELEMENT ("OWNER_MAIL", w.EMAIL),
                                          XMLELEMENT ("ECM_ID", bda.BSC_URL))))
                            FROM SYSDBA.FB_BSC_DOC_ATTACH bda
                                 LEFT JOIN SYSDBA.FB_WORKER w
                                    ON w.USERID = bda.BSC_FILE_WHO
                           WHERE bda.FB_BSC_DOCID = pFB_BSC_DOCID))))).GETCLOBVAL ()
        INTO response_msg
        FROM SYSDBA.FB_BSC_DOC doc
       WHERE doc.FB_BSC_DOCID = pFB_BSC_DOCID;

      RETURN response_msg;
   END;

   FUNCTION GENERATE_ATTR_XML (pFB_BSC_DOCID IN CHAR, pMEMBER IN INTEGER)
      RETURN CLOB
   IS
      response_msg   CLOB;
   BEGIN
      SELECT XMLELEMENT (
                "Request",
                XMLELEMENT ("Application",
                            XMLELEMENT ("TransId", bdc.TRANSID),
                            XMLELEMENT ("LogicalStage", bdc.CHECKTYPE),
                            XMLELEMENT ("RequestId", bdc.REQUESTID),
                            XMLELEMENT ("DateAnket", bdc.STATUSDATE),
                            XMLELEMENT ("Product", 'РБСК КИБ')),
                XMLELEMENT (
                   "DataBlock",
                   XMLELEMENT (
                      "LegalPerson",
                      XMLELEMENT ("ClientType", bdc.CLIENTTYPEID),
                      XMLELEMENT ("RoleUl", bdc.ROLETYPEID),
                      XMLELEMENT (
                         "RegStatus",
                         CASE
                            WHEN acct.RESIDENT = 'Резидент РФ'
                            THEN
                               1
                            WHEN acct.RESIDENT = 'Нерезидент РФ'
                            THEN
                               0
                         END),
                      XMLELEMENT (
                         "lightCheck",
                         CASE
                            WHEN (    pMEMBER = 1
                                  AND bd.BSC_DOC_TYPE IN ('CONTRACT',
                                                          'CONTRACT_PROJ'))
                            THEN
                               0
                            WHEN (    pMEMBER = 1
                                  AND bd.BSC_DOC_TYPE IN ('ARTICLE',
                                                          'ARTICLE_PROJ'))
                            THEN
                               1
                            WHEN (    pMEMBER = 0
                                  AND bd.BSC_DOC_TYPE IN ('CONTRACT',
                                                          'CONTRACT_PROJ'))
                            THEN
                               1
                            WHEN (    pMEMBER = 0
                                  AND bd.BSC_DOC_TYPE IN ('ARTICLE',
                                                          'ARTICLE_PROJ'))
                            THEN
                               0
                         END),
                      XMLELEMENT ("ExtClientId", bdc.ACCOUNTID),
                      XMLELEMENT ("NameOrg", acct.ACCOUNT),
                      XMLELEMENT ("Ogrn", acct.OGRN),
                      XMLELEMENT ("InnLegal", acct.INN),
                      XMLELEMENT ("Kio", acct.KIO)))).GETCLOBVAL ()
        INTO response_msg
        FROM SYSDBA.FB_BSC_DOC bd
             LEFT JOIN SYSDBA.FB_BSC_DOC_CHECK bdc
                ON (bdc.FB_BSC_DOCID = bd.FB_BSC_DOCID)
             LEFT JOIN SYSDBA.ACCOUNT acct
                ON (acct.ACCOUNTID = bdc.ACCOUNTID)
       WHERE bd.FB_BSC_DOCID = pFB_BSC_DOCID AND bdc.MEMBER = pMEMBER;

      RETURN response_msg;
   END;

   FUNCTION MAP_DOC_TO_XML_GD (pFB_BSC_DOCID    IN CHAR,
                               pCORRELATIONID   IN VARCHAR2)
      RETURN CLOB
   IS
      response_msg   CLOB;
   BEGIN
      SELECT XMLELEMENT (
                "OpenAPI",
                XMLELEMENT (
                   "RqUID",
                   UTL_RAW.CAST_TO_VARCHAR2 (
                      UTL_RAW.CAST_TO_RAW (pCORRELATIONID))),
                XMLELEMENT ("MessageType", v_gd_send_document_service_name),
                XMLELEMENT (
                   "Message",
                   XMLELEMENT (
                      "Object",
                      XMLELEMENT (
                         "Document",
                         XMLELEMENT ("CRM_ID", doc.FB_BSC_DOCID),
                         XMLELEMENT ("GD_ID", doc.BSC_GREENDATA_DOC_ID),
                         XMLELEMENT ("DOC_TYPE_ID", doc.BSC_DOC_TYPE),
                         XMLELEMENT ("DOC_TYPE_NAME", doc.BSCDOCTYPETEXT),
                         XMLELEMENT ("DOC_DATE", doc.DOCSTARTDATE),
                         XMLELEMENT ("CUSTOMER_ID", doc.ORDERID),
                         XMLELEMENT ("CONTRACTOR_ID", doc.EXECUTORID),
                         (SELECT XMLELEMENT (
                                    "CLIENT_LIST",
                                    XMLAGG (
                                       XMLELEMENT (
                                          "CLIENT",
                                          XMLELEMENT ("CRM_ID", a.ACCOUNTID),
                                          XMLELEMENT ("CFT_ID",
                                                      a.EXTERNALACCOUNTNO),
                                          XMLELEMENT ("TYPE_ID",
                                                      'LEGAL_PERSON'),
                                          XMLELEMENT ("TYPE_NAME", a.PERSON),
                                          XMLELEMENT ("SEGMENT_ID",
                                                      a.REGIONID),
                                          XMLELEMENT ("SEGMENT_NAME",
                                                      a.CATEGORY),
                                          XMLELEMENT ("SHORTNAME", a.ACCOUNT),
                                          XMLELEMENT ("FULLNAME", a.AKA),
                                          XMLELEMENT ("OKOPF", a.TERRITORY),
                                          XMLELEMENT ("INN", a.INN),
                                          XMLELEMENT ("KPP", a.KPP),
                                          XMLELEMENT ("OGRN", a.OGRN),
                                          XMLELEMENT ("REG_DATE",
                                                      a.REGISTRATIONDATE),
                                          XMLELEMENT (
                                             "IS_RESIDENT",
                                             CASE
                                                WHEN a.RESIDENT =
                                                        'Резидент РФ'
                                                THEN
                                                   'true'
                                                WHEN a.RESIDENT =
                                                        'Нерезидент РФ'
                                                THEN
                                                   'false'
                                             END),
                                          XMLELEMENT ("NON_RES_REG_DATE",
                                                      a.REGISTRATIONDATE),
                                          XMLELEMENT ("NON_RES_REG_NUM",
                                                      a.REGISTRATIONNUMBER),
                                          XMLELEMENT ("IS_TAX_RESIDENT",
                                                      a.RESIDENTTAX),
                                          XMLELEMENT ("COUNTRY", ad.COUNTRY),
                                          XMLELEMENT ("KIO", a.KIO),
                                          XMLELEMENT (
                                             "REG_ADDRESS",
                                                ad.ADDRESS1
                                             || ' '
                                             || ad.ADDRESS2),
                                          XMLELEMENT ("ORG_ID", a.REGION),
                                          XMLELEMENT ("CREATED_EMP",
                                                      worker.EMAIL))))
                            FROM SYSDBA.ACCOUNT a
                                 LEFT JOIN
                                 (SELECT ad1.*,
                                         ROW_NUMBER ()
                                         OVER (PARTITION BY ad1.ENTITYID
                                               ORDER BY ad1.ENTITYID)
                                            AS row_rank
                                    FROM SYSDBA.ADDRESS ad1) ad
                                    ON     ad.ENTITYID = a.ACCOUNTID
                                       AND ad.row_rank = 1
                           WHERE    a.ACCOUNTID = doc.ORDERID
                                 OR a.ACCOUNTID = doc.EXECUTORID),
                         XMLELEMENT ("DOC_PLAN_END_DATE", doc.FINPLANDATE),
                         XMLELEMENT ("DOC_NUM", doc.DOCNUMBER),
                         XMLELEMENT ("IS_FRAMEWORK",
                                     BOOL_TO_STRING (doc.ISFRAMEWORK)),
                         (SELECT XMLELEMENT (
                                    "DOC_SUBJECT_TYPE_LIST",
                                    XMLAGG (
                                       XMLELEMENT (
                                          "DOC_SUBJECT_TYPE",
                                          XMLELEMENT ("ID", t1.SUBJ_TYPE),
                                          XMLELEMENT ("NAME", t2.TEXT))))
                            FROM ( (    SELECT TRIM (
                                                  REGEXP_SUBSTR (
                                                     (SELECT DOCSUBJTYPE -- Костыль (Oracle не видит doc.DOCSUBTYPE из-за тройной вложенности...)
                                                        FROM SYSDBA.FB_BSC_DOC
                                                       WHERE FB_BSC_DOCID =
                                                                pFB_BSC_DOCID),
                                                     '[^;]+',
                                                     1,
                                                     LEVEL))
                                                  SUBJ_TYPE
                                          FROM DUAL
                                    CONNECT BY LEVEL <=
                                                    REGEXP_COUNT (
                                                       (SELECT DOCSUBJTYPE -- Костыль (Oracle не видит doc.DOCSUBTYPE из-за тройной вложенности...)
                                                          FROM SYSDBA.FB_BSC_DOC
                                                         WHERE FB_BSC_DOCID =
                                                                  pFB_BSC_DOCID),
                                                       ';')
                                                  + 1) t1
                                  JOIN SYSDBA.PICKLIST t2
                                     ON     PICKLISTID IN (SELECT ITEMID
                                                             FROM SYSDBA.PICKLIST
                                                            WHERE TEXT =
                                                                     'Тип предмета Договора БСК')
                                        AND SHORTTEXT = t1.SUBJ_TYPE)),
                         XMLELEMENT ("DOC_SUBJECT", doc.DOCSUBJ),
                         XMLELEMENT (
                            "DOC_BANK_RECEIVE_DATE",
                            TO_CHAR (doc.DOC_BANK_RECEIVE,
                                     'yyyy-mm-dd"T"HH:mm:ss')),
                         XMLELEMENT ("DELIV_PAYMENT_TERMS", doc.PAY_WARRANTY),
                         XMLELEMENT ("OPEN_NECESSARITY_ID",
                                     doc.OBSNECESSARITY),
                         XMLELEMENT (
                            "OPEN_NECESSARITY_NAME",
                            TRANSLATE_VALUE_BY_DICTIONARY (
                               doc.OBSNECESSARITY,
                               'Необходимость открытия банковского счета БСК')),
                         XMLELEMENT ("ACC_OPEN_NEED_ID", doc.OBS_NEED),
                         XMLELEMENT (
                            "ACC_OPEN_NEED_NAME",
                            TRANSLATE_VALUE_BY_DICTIONARY (
                               doc.OBS_NEED,
                               'Целевое назначение счета БСК')),
                         XMLELEMENT ("BSC_TYPE_ID", doc.BSC_TYPE),
                         XMLELEMENT (
                            "BSC_TYPE_NAME",
                            TRANSLATE_VALUE_BY_DICTIONARY (doc.BSC_TYPE,
                                                           'Виды БСК')),
                         XMLELEMENT ("AGREE_MIN_SUM", doc.VALUE_MIN),
                         XMLELEMENT ("AGREE_MIN_ADV_SUM",
                                     doc.ADVANCE_VALUE_MIN),
                         XMLELEMENT ("AGREE_MIN_TOTAL_SUM",
                                     doc.ARTICLE_OUT_VALUE_MIN),
                         XMLELEMENT ("DOC_SUM", doc.VALUE_AND_NDS),
                         XMLELEMENT (
                            "VAT_SUM",
                            CASE
                               WHEN doc.VALUE_NDS IS NULL THEN 0
                               ELSE doc.VALUE_NDS
                            END),
                         XMLELEMENT ("DOC_CURRENCY", doc.CURRENCY),
                         XMLELEMENT ("SERVICE_CALC_MODE_ID",
                                     doc.H_CONTRACTOR_PAYMENT_METHOD),
                         XMLELEMENT (
                            "SERVICE_CALC_MODE_NAME",
                            TRANSLATE_VALUE_BY_DICTIONARY (
                               doc.H_CONTRACTOR_PAYMENT_METHOD,
                               'Способ расчета БСК')),
                         XMLELEMENT ("SERVICE_SUM_PERCENT",
                                     doc.H_CONTRACTOR_PAYMENT_PER),
                         XMLELEMENT ("SERVICE_SUM", doc.H_CONTRACTOR_VALUE),
                         XMLELEMENT ("IS_ADV_PAY_AVAILABLE",
                                     BOOL_TO_STRING (doc.ADVANCE_PAYMENT)),
                         XMLELEMENT ("ADV_CALC_MODE_ID",
                                     doc.ADVANCE_PAYMENT_METHOD),
                         XMLELEMENT (
                            "ADV_CALC_MODE_NAME",
                            TRANSLATE_VALUE_BY_DICTIONARY (
                               doc.ADVANCE_PAYMENT_METHOD,
                               'Способ расчета БСК')),
                         XMLELEMENT ("ADV_SUM_PERCENT",
                                     doc.ADVANCE_PAYMENT_PER),
                         XMLELEMENT ("ADV_FIX_SUM", doc.ADVANCE_VALUE),
                         XMLELEMENT ("ADV_ORDER_SET_ID", doc.ADVANCE_ORDER),
                         XMLELEMENT (
                            "ADV_ORDER_SET_NAME",
                            TRANSLATE_VALUE_BY_DICTIONARY (
                               doc.ADVANCE_ORDER,
                               'Порядок зачета аванса БСК')),
                         XMLELEMENT ("WARANTY_KEEP_ID", doc.RETENTION),
                         XMLELEMENT (
                            "WARANTY_KEEP_NAME",
                            TRANSLATE_VALUE_BY_DICTIONARY (
                               doc.RETENTION,
                               'Способ расчета БСК')),
                         XMLELEMENT ("WAR_KEEP_FIX_SUM", doc.RETENTION_VALUE),
                         XMLELEMENT ("WAR_KEEP_SUM_PERC",
                                     doc.RETENTION_PAYMENT_PER),
                         XMLELEMENT ("OTHER_KEEP_MODE_ID",
                                     doc.RETENTION_OTHER),
                         XMLELEMENT (
                            "OTHER_KEEP_MODE_NAME",
                            TRANSLATE_VALUE_BY_DICTIONARY (
                               doc.RETENTION_OTHER,
                               'Способ расчета БСК')),
                         XMLELEMENT ("OTHER_KEEP_FIX_SUM",
                                     doc.RETENTION_OTHER_VALUE),
                         XMLELEMENT ("OTHER_KEEP_SUM_PERC",
                                     doc.RETENTION_OTHER_PER),
                         XMLELEMENT ("IS_ADV_PAY_NEED_DOCS",
                                     BOOL_TO_STRING (doc.ADVANCE_DOC_NEED)),
                         XMLELEMENT ("VALID_WP_DOC_LIST",
                                     doc.CONTRACT_DPVR_DOC_TYPE),
                         XMLELEMENT ("STATEMENT_ITEM_LIST"),
                         XMLELEMENT ("ADV_ITEM_SUM"),
                         XMLELEMENT ("DOC_SUBITEM_ID"),
                         XMLELEMENT ("ADV_SUM_SUBITEM_ID"),
                         XMLELEMENT ("LADV_SUM_SUBITEM_ID"),
                         XMLELEMENT ("ORG_ID", doc.FILIAL_ID),
                         XMLELEMENT ("CREATED_EMP", worker.EMAIL),
                         XMLELEMENT ("PREV_DOC_ID", doc.PARENT_DOC_ID),
                         XMLELEMENT ("REL_PROJECT_ID", doc.DOCPROJECTID),
                         XMLELEMENT ("CONTRACT_TREATY_ID"),
                         XMLELEMENT ("IS_MAIN_ATR_NO_CHANGE"),
                         XMLELEMENT ("DOC_SUM_CHANGE_ID"),
                         XMLELEMENT ("DOC_SUM_CHANGE_NAME"),
                         XMLELEMENT ("OTHER_KEEP_CHANGE_ID"),
                         XMLELEMENT ("OTHER_KEEP_CHANGE_NAME"),
                         XMLELEMENT ("WAR_KEEP_CHANGE_ID"),
                         XMLELEMENT ("WAR_KEEP_CHANGE_NAME"),
                         XMLELEMENT ("ADVANCE_CHANGE_ID"),
                         XMLELEMENT ("ADVANCE_CHANGE_NAME"),
                         XMLELEMENT ("SERVICE_CHANGE_ID"),
                         XMLELEMENT ("SERVICE_CHANGE_NAME"),
                         XMLELEMENT ("ADD_AGR_COMMENT"),
                         XMLELEMENT ("CHANGE_REASON_COM"),
                         XMLELEMENT ("ADD_AGREEMENT_DATE"),
                         (SELECT XMLELEMENT (
                                    "ATTACHED_FILE_LIST",
                                    XMLAGG (
                                       XMLELEMENT (
                                          "ATTACHED_FILE",
                                          XMLELEMENT (
                                             "FILENAME",
                                                bda.BSC_FILE_NAME
                                             || '.'
                                             || bda.BSC_FILE_EXT),
                                          XMLELEMENT ("FILE_SIZE",
                                                      bda.BSC_FILE_SIZE),
                                          XMLELEMENT ("CREATION_DATE",
                                                      bda.BSC_FILE_DATE),
                                          XMLELEMENT ("NOTES",
                                                      bda.BSC_FILE_DESCR),
                                          XMLELEMENT ("OWNER_MAIL", w.EMAIL),
                                          XMLELEMENT ("ECM_ID", bda.BSC_URL))))
                            FROM SYSDBA.FB_BSC_DOC_ATTACH bda
                                 LEFT JOIN SYSDBA.FB_WORKER w
                                    ON w.USERID = bda.BSC_FILE_WHO
                           WHERE bda.FB_BSC_DOCID = pFB_BSC_DOCID),
                         (SELECT XMLELEMENT (
                                    "CONTACT_LIST",
                                    XMLAGG (
                                       XMLELEMENT (
                                          "CONTACT",
                                          XMLELEMENT (
                                             "ID",
                                             bdc.FB_BSC_DOC_CONTACTID),
                                          XMLELEMENT ("RELATION",
                                                      bdc.BSC_CONT_RELATION),
                                          XMLELEMENT ("LASTNAME",
                                                      bdc.BSC_CONT_LASTNAME),
                                          XMLELEMENT ("FIRSTNAME",
                                                      bdc.BSC_CONT_FIRSTNAME),
                                          XMLELEMENT (
                                             "MIDDLENAME",
                                             bdc.BSC_CONT_MIDDLENAME),
                                          XMLELEMENT ("GENDER",
                                                      bdc.BSC_CONT_GENDER),
                                          XMLELEMENT ("TITLE",
                                                      bdc.BSC_CONT_TITLE),
                                          XMLELEMENT ("WORKPHONE",
                                                      bdc.BSC_CONT_WORKPHONE),
                                          XMLELEMENT ("MOBILE",
                                                      bdc.BSC_CONT_MOBILE),
                                          XMLELEMENT ("EMAIL",
                                                      bdc.BSC_CONT_EMAIL),
                                          XMLELEMENT ("NOTES",
                                                      bdc.BSC_CONT_NOTES),
                                          XMLELEMENT (
                                             "CREATEDATE",
                                             bdc.BSC_CONT_CREATEDATE))))
                            FROM SYSDBA.FB_BSC_DOC_CONTACT bdc
                           WHERE bdc.FB_BSC_DOCID = pFB_BSC_DOCID),
                         XMLELEMENT ("BANK_ACC_ID"),
                         XMLELEMENT ("STATUS_ID", doc.DOC_STATUS),
                         XMLELEMENT ("STATUS_NAME", doc.DOC_STATUS_TEXT),
                         XMLELEMENT ("STATUS_LAST_CHANGE",
                                     doc.DOC_STATUS_LAST_CHANGE),
                         XMLELEMENT ("DOC_SOURCE_ID", doc.DOC_SOURCE),
                         XMLELEMENT (
                            "DOC_SOURCE_NAME",
                            TRANSLATE_VALUE_BY_DICTIONARY (
                               doc.DOC_SOURCE,
                               'Источник поступления карточки БСК')))))).GETCLOBVAL ()
        INTO response_msg
        FROM SYSDBA.FB_BSC_DOC doc
             LEFT JOIN SYSDBA.V_FB_WORKER worker
                ON (worker.USERID = doc.BSC_DOC_USER_ID)
       WHERE doc.FB_BSC_DOCID = pFB_BSC_DOCID;

      RETURN response_msg;
   END;


   FUNCTION MAP_STATEMENT_TO_XML_GD (pFB_BSC_DOCID IN CHAR)
      RETURN CLOB
   IS
      response_msg   CLOB;
   BEGIN
      SELECT XMLELEMENT (
                "OpenAPI",
                XMLELEMENT ("MessageType", v_gd_send_statement_service_name),
                XMLELEMENT (
                   "Message",
                   XMLELEMENT (
                      "Object",
                      XMLELEMENT (
                         "Statement",
                         XMLELEMENT ("CRM_ID", doc.FB_BSC_DOCID),
                         XMLELEMENT ("GD_ID", doc.BSC_GREENDATA_DOC_ID),
                         XMLELEMENT ("BANK_ACC_ID", doc.OBS_ACCOUNT_NUM),
                         XMLELEMENT ("BANK_ACC_BIC", doc.OBSACCOUNTBIC),
                         XMLELEMENT ("BANK_ACC_CFT_ID", doc.OBSACCOUNTCFTID),
                         XMLELEMENT ("BANK_ACC_OWNER_CRM_ID",
                                     doc.OBSACCOWNERCRMID),
                         XMLELEMENT ("BANK_ACC_OWNER_CFT_ID",
                                     doc.OBSACCOWNERCFTID),
                         XMLELEMENT ("DOC_NUM", doc.DOCNUMBER),
                         XMLELEMENT ("DOC_DATE", doc.DOCSTARTDATE),
                         XMLELEMENT (
                            "RECEIVE_DATE",
                            TO_CHAR (doc.DOC_BANK_RECEIVE,
                                     'yyyy-mm-dd"T"HH24:mi:ss')),
                         XMLELEMENT ("STATEMENT_AMOUNT", doc.VALUE_AND_NDS),
                         XMLELEMENT ("ORG_ID", doc.FILIAL_ID),
                         XMLELEMENT ("CREATED_EMP", wrk.EMAIL),
                         XMLELEMENT ("DOC_SOURCE_ID", doc.DOC_SOURCE),
                         XMLELEMENT (
                            "DOC_SOURCE_NAME",
                            TRANSLATE_VALUE_BY_DICTIONARY (
                               doc.DOC_SOURCE,
                               'Источник поступления карточки БСК')),
                         XMLELEMENT ("STATUS_ID", doc.DOC_STATUS),
                         XMLELEMENT ("STATUS_NAME", doc.DOC_STATUS_TEXT),
                         XMLELEMENT ("STATUS_LAST_CHANGE",
                                     doc.DOC_STATUS_LAST_CHANGE),
                         XMLELEMENT ("DOC_VERSION", doc.DOC_VERSION),
                         (SELECT XMLELEMENT (
                                    "ATTACHED_FILE_LIST",
                                    XMLAGG (
                                       XMLELEMENT (
                                          "ATTACHED_FILE",
                                          XMLELEMENT (
                                             "FILENAME",
                                                bda.BSC_FILE_NAME
                                             || '.'
                                             || bda.BSC_FILE_EXT),
                                          XMLELEMENT ("FILE_SIZE",
                                                      bda.BSC_FILE_SIZE),
                                          XMLELEMENT ("CREATION_DATE",
                                                      bda.BSC_FILE_DATE),
                                          XMLELEMENT ("NOTES",
                                                      bda.BSC_FILE_DESCR),
                                          XMLELEMENT ("OWNER_MAIL", w.EMAIL),
                                          XMLELEMENT ("ECM_ID", bda.BSC_URL))))
                            FROM SYSDBA.FB_BSC_DOC_ATTACH bda
                                 LEFT JOIN SYSDBA.V_FB_WORKER w
                                    ON w.USERID = bda.BSC_FILE_WHO
                           WHERE bda.FB_BSC_DOCID = pFB_BSC_DOCID),
                         XMLELEMENT ("INTERNAL_ID", doc.EXPENSE_SHEET_ID),
                         XMLELEMENT ("INTERNAL_PARENT_ID",
                                     doc.EXPENSE_SHEET_PARENT),
                         (SELECT XMLELEMENT (
                                    "BACKING_DOC_LIST",
                                    XMLAGG (
                                       XMLELEMENT (
                                          "BACKING_DOC",
                                          XMLELEMENT ("ID", bdr.DOCID))))
                            FROM SYSDBA.FB_BSC_ES_DOC_RELATION bdr
                           WHERE bdr.STATEMENTID = pFB_BSC_DOCID),
                         XMLELEMENT ("CONTRACT_ID",
                                     doc.EXPENSESHEETCONTRACTID))))).GETCLOBVAL ()
        INTO response_msg
        FROM SYSDBA.FB_BSC_DOC doc
             LEFT JOIN SYSDBA.V_FB_WORKER wrk
                ON (wrk.USERID = doc.BSC_DOC_USER_ID)
       WHERE doc.FB_BSC_DOCID = pFB_BSC_DOCID;

      RETURN response_msg;
   END;


   FUNCTION STRING_TO_BOOL (STR IN VARCHAR2)
      RETURN CHAR
   IS
   BEGIN
      RETURN CASE
                WHEN LOWER (STR) = 'true' THEN 'T'
                WHEN LOWER (STR) = 'false' THEN 'F'
                ELSE NULL
             END;
   END;

   FUNCTION BOOL_TO_STRING (STR IN VARCHAR2)
      RETURN CHAR
   IS
   BEGIN
      RETURN CASE
                WHEN STR = 'T' THEN 'True'
                WHEN STR = 'F' THEN 'False'
                ELSE NULL
             END;
   END;

   PROCEDURE SEND_EMAIL (pTitle   IN VARCHAR2,
                         pBody    IN VARCHAR2,
                         pEmail   IN VARCHAR2)
   IS
   BEGIN
      IF (pEmail IS NULL OR pEmail = '')
      THEN
         RETURN;
      END IF;

      INSERT INTO SYSDBA.FB_SEND_EMAIL (FB_SEND_EMAILID,
                                        CREATEUSER,
                                        CREATEDATE,
                                        MODIFYUSER,
                                        MODIFYDATE,
                                        EMAIL,
                                        EMAIL_BODY,
                                        EMAIL_SUBJECT,
                                        STATUS,
                                        TRY_TO_SEND_COUNT)
              VALUES (
                        SYSDBA.FCREATESLXID ('FB_SEND_EMAIL'),
                        'ADMIN       ',
                        SYS_EXTRACT_UTC (SYSTIMESTAMP),
                        'ADMIN       ',
                        SYS_EXTRACT_UTC (SYSTIMESTAMP),
                        pEmail,
                           '<html>
                                <body lang="RU" style=" padding: 0; margin: 0; font-family: "Segoe UI", Tahoma, Geneva, Verdana, sans-serif; font-size: 14px; ">
                                    <table border="0" cellspacing="0" cellpadding="0" width="100%" style="width: 100%; background-color: #f2f2f2; border-collapse: collapse;">
                                        <tr>
                                            <td width="100%" valign="middle" align="center" style="width: 100%; padding: 16px 16px 16px 16px;">
                                                <table border="0" cellspacing="0" cellpadding="0" style=" max-width: 90%; min-width: 70%; border-collapse: collapse; background-color: white; ">
                                                    <tr>
                                                        <td width="100%" valign="top" style="width: 100%; padding: 16px 16px 16px 16px;">'
                        || pBody
                        || '</td>
                                                    </tr>
                                                </table>
                                            </td>
                                        </tr>
                                    </table>
                                </body>
                            </html>',
                        'Infor CRM. РБСК/БСК. ' || pTitle,
                        'PREPARE',
                        0);

      COMMIT;
   END;

   PROCEDURE SEND_EMAIL_ABOUT_SEND_DOCUMENT (pFB_BSC_DOCID IN VARCHAR2)
   IS
      v_bsc_doc         SYSDBA.FB_BSC_DOC%ROWTYPE;
      v_account_info    VARCHAR (140) := '';
      v_apprlog_table   VARCHAR (2000) := '';
      v_domain          VARCHAR (256) := '';
   BEGIN
      BEGIN
         SELECT *
           INTO v_bsc_doc
           FROM SYSDBA.FB_BSC_DOC
          WHERE FB_BSC_DOCID = pFB_BSC_DOCID;
      EXCEPTION
         WHEN OTHERS
         THEN
            v_bsc_doc := NULL;
      END;

      BEGIN
         SELECT DATAVALUE
           INTO v_domain
           FROM SYSDBA.CUSTOMSETTINGS
          WHERE CATEGORY = 'InforCRMHyperLink' AND ROWNUM = 1;
      EXCEPTION
         WHEN OTHERS
         THEN
            NULL;
      END;

      BEGIN
         SELECT (acnt.ACCOUNT || ' ' || acnt.INN)
           INTO v_account_info
           FROM SYSDBA.ACCOUNT acnt
                JOIN SYSDBA.FB_BSC_DOC bd ON BD.EXECUTORID = acnt.ACCOUNTID
          WHERE bd.FB_BSC_DOCID = pFB_BSC_DOCID;
      EXCEPTION
         WHEN OTHERS
         THEN
            NULL;
      END;

      BEGIN
           SELECT LISTAGG (
                        '<tr><td>'
                     || aa.BSC_RESPONSIBLEOFFICER
                     || '</td><td>'
                     || aa.BSC_DIVISIONNAME
                     || '</td><td>'
                     || p2.TEXT
                     || '</td><td>'
                     || aa.BSC_NOTES
                     || '</td><td>',
                     '</tr>')
                  WITHIN GROUP (ORDER BY aa.CREATEDATE)
             INTO v_apprlog_table
             FROM SYSDBA.FB_BSC_APPR_LOG aa
                  LEFT JOIN SYSDBA.PICKLIST p2 ON p2.SHORTTEXT = aa.BSC_STATE
                  LEFT JOIN SYSDBA.PICKLIST p1 ON p2.PICKLISTID = p1.ITEMID
            WHERE     FB_BSC_DOCID = pFB_BSC_DOCID
                  AND p1.PickListId = 'PICKLISTLIST'
                  AND p1.Text =
                         'Статус Карточки документа БСК'
         ORDER BY aa.CREATEDATE;
      EXCEPTION
         WHEN OTHERS
         THEN
            NULL;
      END;

      -- Оповещение о смене статуса
      FOR F
         IN (SELECT DISTINCT W.EMAIL
               FROM SYSDBA.V_FB_WORKER W
                    INNER JOIN SYSDBA.USERROLE UR ON UR.USERID = W.USERID
                    INNER JOIN SYSDBA.ROLE R ON R.ROLEID = UR.ROLEID
              WHERE    LOWER (R.ROLENAME) =
                          LOWER ('Исполнитель Бэк-офиса')
                    OR     W.USERID = (SELECT BSC_DOC_USER_ID
                                         FROM SYSDBA.FB_BSC_DOC
                                        WHERE FB_BSC_DOCID = pFB_BSC_DOCID)
                       AND W.EMAIL IS NOT NULL)
      LOOP
         SEND_EMAIL (
               'Получен результат согласования '
            || NM_CRM.BSC_PKG.MAP_BSCDOCTYPE_TO_TEXT_GENETIVE (
                  v_bsc_doc.BSC_DOC_TYPE)
            || '. Клиент: '
            || v_account_info,
               'Согласование <a href="'
            || v_domain
            || 'FbBscDoc.aspx?entityid='
            || pFB_BSC_DOCID
            || '&'
            || 'modeid=detail">'
            || (v_bsc_doc.BSCDOCTYPETEXT || ' ' || v_bsc_doc.DOCNUMBER)
            || ' от '
            || TO_CHAR (v_bsc_doc.DOCSTARTDATE, 'dd.MM.yyyy')
            || '</a> завершено. Карточка '
            || NM_CRM.BSC_PKG.MAP_BSCDOCTYPE_TO_TEXT_GENETIVE (
                  v_bsc_doc.BSC_DOC_TYPE)
            || ' переведена в статус '
            || v_bsc_doc.DOC_STATUS_TEXT
            || '<p><table><tr><th>Согласователь</th><th>Подразделение</th><th>Статус</th><th>Примечания</th></tr>'
            || v_apprlog_table
            || '</table></p>',
            F.EMAIL);
      END LOOP;
   END;

   PROCEDURE ENQUEUE_MESSAGE (TEXT             IN     CLOB,
                              SERVICENAME      IN     VARCHAR2,
                              CORRELATION_ID   IN     VARCHAR2,
                              QUEUE_NAME       IN     VARCHAR2,
                              MSGID_OUT           OUT RAW)
   IS
      MESSAGE              SYS.aq$_jms_text_message;
      enqueue_options      DBMS_AQ.ENQUEUE_OPTIONS_T;
      message_properties   DBMS_AQ.MESSAGE_PROPERTIES_T;
      msgid                RAW (16);
   BEGIN
      MESSAGE := sys.aq$_jms_text_message.construct;
      message_properties.correlation := CORRELATION_ID;
      MESSAGE.set_text (TEXT);
      MESSAGE.set_string_property ('SERVICENAME', SERVICENAME);

      DBMS_AQ.enqueue (queue_name           => QUEUE_NAME,
                       enqueue_options      => enqueue_options,
                       message_properties   => message_properties,
                       payload              => MESSAGE,
                       msgid                => msgid);
      MSGID_OUT := msgid;
   END;

   PROCEDURE SEND_STATEMENT_TO_GD_P (pFB_BSC_DOCID IN CHAR)
   IS
      v_outmsg_id                RAW (16);
      v_fulloutmsg               CLOB;
      v_correlation_id           VARCHAR2 (32) := '123';        --SYS_GUID ();
      v_response                 CLOB;
      v_response_exception_msg   VARCHAR2 (512);
      v_error_msg                VARCHAR2 (512);
      v_expiration_time          NUMBER (12);
   BEGIN
      -- Получаем время ожидания из пользовательских настроек
      BEGIN
         SELECT TO_NUMBER (DATAVALUE,
                           'FM99999999999999999D9999',
                           'nls_numeric_characters = ''. ''')
           INTO v_expiration_time
           FROM SYSDBA.CUSTOMSETTINGS
          WHERE     CATEGORY = 'Bank Support Contract'
                AND DESCRIPTION = 'BSC_Contraparty_GD_Check_Timeout';
      EXCEPTION
         WHEN OTHERS
         THEN
            v_expiration_time := NULL;
      END;

      -- Формируем XML
      SELECT NM_CRM.BSC_PKG.MAP_STATEMENT_TO_XML_GD (pFB_BSC_DOCID)
        INTO v_fulloutmsg
        FROM DUAL;

      -- Отправляем XML
      NM_CRM.BSC_PKG.ENQUEUE_MESSAGE (v_fulloutmsg,
                                      v_gd_send_statement_service_name,
                                      v_correlation_id,
                                      v_crm_gd_queue_out,
                                      v_outmsg_id);

      -- Пишем в лог XML которую отправляем
      INSERT INTO NM_CRM.FB_BSC_LOG (CORRELATION_ID,
                                     CREATEDATE,
                                     XML_TEXT,
                                     QUEUE_NAME,
                                     SERVICE_NAME,
                                     ENTITYID)
           VALUES (v_correlation_id,
                   SYS_EXTRACT_UTC (SYSTIMESTAMP),
                   v_fulloutmsg,
                   v_crm_gd_queue_out,
                   v_gd_send_statement_service_name,
                   pFB_BSC_DOCID);

      COMMIT;

      NM_CRM.fb_listen_queue (v_crm_gd_queue_in,
                              v_expiration_time,
                              v_correlation_id,
                              v_response,
                              v_response_exception_msg);

      -- Если вышло время ожидания ответа
      IF (v_response_exception_msg = 'no_message')
      THEN
         UPDATE SYSDBA.FB_BSC_DOC
            SET DOC_STATUS = 'DOC_TO_GD_ERR',
                DOC_STATUS_REASON =
                   'Вышло время ожидания ответа от GreenData'
          WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

         COMMIT;

         UPDATE SYSDBA.FB_BSC_DOC
            SET DOC_STATUS = 'NEW'
          WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

         COMMIT;
         RETURN;
      END IF;

      -- Пишем в лог XML которой ответили GD
      INSERT INTO NM_CRM.FB_BSC_LOG (CORRELATION_ID,
                                     CREATEDATE,
                                     XML_TEXT,
                                     QUEUE_NAME,
                                     SERVICE_NAME,
                                     ENTITYID)
           VALUES (v_correlation_id,
                   SYS_EXTRACT_UTC (SYSTIMESTAMP),
                   v_response,
                   v_crm_gd_queue_in,
                   v_crm_send_reponse_service_name,
                   pFB_BSC_DOCID);

      COMMIT;

      FOR responseEntity
         IN (     SELECT RESP.*
                    FROM XMLTABLE (
                            '/OpenAPI/Message/Object/Response'
                            PASSING XMLTYPE (v_response)
                            COLUMNS CRM_ID     VARCHAR2 (12) PATH 'CRM_ID',
                                    GD_ID      INTEGER PATH 'GD_ID',
                                    MSG_CODE   INTEGER PATH 'MESSAGE_CODE',
                                    MSG        VARCHAR2 (128) PATH 'MESSAGE') RESP)
      LOOP
         IF (responseEntity.MSG_CODE IN (1, 3, 4))
         THEN
            UPDATE SYSDBA.FB_BSC_DOC
               SET DOC_STATUS = 'DOC_TO_GD_ERR', DOC_STATUS_REASON = NULL
             WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

            COMMIT;

            UPDATE SYSDBA.FB_BSC_DOC
               SET DOC_STATUS = 'MEMBER_CHECK_POS'
             WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

            COMMIT;
         ELSIF (responseEntity.MSG_CODE = 0)
         THEN
            UPDATE SYSDBA.FB_BSC_DOC
               SET DOC_STATUS = 'ON_CHECK',
                   BSC_GREENDATA_DOC_ID = responseEntity.GD_ID,
                   DOC_STATUS_REASON =
                      'Получен статус из GreenData'
             WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

            COMMIT;
         ELSIF (responseEntity.MSG_CODE = 2)
         THEN
            UPDATE SYSDBA.FB_BSC_DOC
               SET DOC_STATUS = responseEntity.MSG,
                   BSC_GREENDATA_DOC_ID = responseEntity.GD_ID,
                   DOC_STATUS_REASON =
                      'Карточка уже создана на стороне GreenData'
             WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

            COMMIT;
         ELSE
            UPDATE SYSDBA.FB_BSC_DOC
               SET DOC_STATUS = 'DOC_TO_GD_ERR',
                   DOC_STATUS_REASON =
                      'Получен неопознанный тип запроса.'
             WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

            COMMIT;

            UPDATE SYSDBA.FB_BSC_DOC
               SET DOC_STATUS = 'NEW'
             WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

            COMMIT;
         END IF;
      END LOOP;

      COMMIT;
   EXCEPTION
      WHEN OTHERS
      THEN
         v_error_msg := SQLERRM;

         INSERT INTO NM_CRM.FB_BSC_LOG (CORRELATION_ID,
                                        CREATEDATE,
                                        XML_TEXT,
                                        QUEUE_NAME,
                                        SERVICE_NAME,
                                        ENTITYID,
                                        EXCEPTION_MSG)
              VALUES (v_correlation_id,
                      SYS_EXTRACT_UTC (SYSTIMESTAMP),
                      v_response,
                      v_crm_gd_queue_in,
                      'Exception',
                      pFB_BSC_DOCID,
                      v_error_msg);

         COMMIT;
   END;

   PROCEDURE SEND_STATEMENT_TO_GD (pFB_BSC_DOCID IN CHAR)
   IS
   BEGIN
      DBMS_SCHEDULER.create_job (
         job_name     =>    'NM_CRM.FB_BSC_SEND_STATEMENT_TO_GD_JOB_'
                         || pFB_BSC_DOCID,
         job_type     => 'PLSQL_BLOCK',
         job_action   =>    'begin NM_CRM.BSC_PKG.SEND_STATEMENT_TO_GD_P('''
                         || pFB_BSC_DOCID
                         || '''); end;',
         start_date   => SYSDATE,
         enabled      => TRUE,
         auto_drop    => TRUE,
         comments     => 'one-time job');
   EXCEPTION
      WHEN OTHERS
      THEN
         NULL;
   END;

   PROCEDURE SEND_MEMBER_TO_ATTR (pMEMBER                     IN NUMBER,
                                  pMEMBERID                   IN CHAR,
                                  pFB_BSC_DOCID               IN CHAR,
                                  pUSERID                     IN CHAR,
                                  pCORRELATIONID              IN VARCHAR2,
                                  pNEED_TO_SKIP_CHECK_ORDER   IN CHAR)
   IS
      isClientCheckExists   CHAR (1) := 'T';
      transId               VARCHAR2 (64)
         := CASE WHEN pMEMBER = 0 THEN '123' ELSE '124' END;   -- SYS_GUID ();
      requestId             VARCHAR2 (64)
         := CASE WHEN pMEMBER = 0 THEN '123' ELSE '124' END;   -- SYS_GUID ();
      xmlText               CLOB;
      outMsgId              RAW (16);
   BEGIN
      SELECT CASE
                WHEN EXISTS
                        (SELECT 1
                           FROM SYSDBA.FB_BSC_DOC_CHECK
                          WHERE     FB_BSC_DOCID = pFB_BSC_DOCID
                                AND "MEMBER" = pMEMBER)
                THEN
                   'T'
                ELSE
                   'F'
             END
        INTO isClientCheckExists
        FROM DUAL;

      IF (isClientCheckExists = 'T')
      THEN
         UPDATE SYSDBA.FB_BSC_DOC_CHECK
            SET DESICIONNAME = NULL,
                DESICIONTYPE =
                   CASE
                      WHEN (pNEED_TO_SKIP_CHECK_ORDER = 'T' AND pMEMBER = 0)
                      THEN
                         4
                      ELSE
                         NULL
                   END,
                CHECKCOMMENT = NULL,
                CODEERROR = NULL,
                TRANSID = transId,
                REQUESTID = requestId,
                MODIFYDATE = SYS_EXTRACT_UTC (SYSTIMESTAMP),
                MODIFYUSER = pUSERID
          WHERE FB_BSC_DOCID = pFB_BSC_DOCID AND "MEMBER" = pMEMBER;
      ELSE
         INSERT INTO SYSDBA.FB_BSC_DOC_CHECK (TRANSID,
                                              STATUSDATE,
                                              ROLETYPEID,
                                              REQUESTID,
                                              MODIFYUSER,
                                              MODIFYDATE,
                                              "MEMBER",
                                              FB_BSC_DOC_CHECKID,
                                              FB_BSC_DOCID,
                                              CREATEUSER,
                                              CREATEDATE,
                                              CLIENTTYPEID,
                                              ACCOUNTID,
                                              CHECKTYPE,
                                              DESICIONTYPE)
            SELECT transId,
                   SYS_EXTRACT_UTC (SYSTIMESTAMP),
                   1,
                   requestId,
                   pUSERID,
                   SYS_EXTRACT_UTC (SYSTIMESTAMP),
                   pMEMBER,
                   SYSDBA.FCREATESLXID ('FB_BSC_DOC_CHECK'),
                   pFB_BSC_DOCID,
                   pUSERID,
                   SYS_EXTRACT_UTC (SYSTIMESTAMP),
                   CASE
                      WHEN (acct.RESIDENT = 'Резидент РФ')
                      THEN
                         (CASE
                             WHEN LENGTH (acct.INN) = 10 THEN 1
                             WHEN LENGTH (acct.INN) = 12 THEN 2
                          END)
                      WHEN (acct.RESIDENT = 'Нерезидент РФ')
                      THEN
                         2
                   END,
                   pMEMBERID,
                   1,
                   CASE
                      WHEN (pNEED_TO_SKIP_CHECK_ORDER = 'T' AND pMEMBER = 0)
                      THEN
                         4
                      ELSE
                         NULL
                   END
              FROM SYSDBA.FB_BSC_DOC doc
                   LEFT JOIN SYSDBA.ACCOUNT acct
                      ON (acct.ACCOUNTID = pMEMBERID)
             WHERE doc.FB_BSC_DOCID = pFB_BSC_DOCID;
      END IF;

      COMMIT;

      IF (pNEED_TO_SKIP_CHECK_ORDER = 'T' AND pMEMBER = 0)
      THEN
         RETURN;
      END IF;

      xmlText := NM_CRM.BSC_PKG.GENERATE_ATTR_XML (pFB_BSC_DOCID, pMEMBER);

      -- Отправка XML
      NM_CRM.BSC_PKG.ENQUEUE_MESSAGE (xmlText,
                                      v_attr_send_request_service_name,
                                      pCORRELATIONID,
                                      v_crm_attr_queue_out,
                                      outMsgId);

      INSERT INTO NM_CRM.FB_BSC_LOG (CORRELATION_ID,
                                     CREATEDATE,
                                     XML_TEXT,
                                     QUEUE_NAME,
                                     SERVICE_NAME,
                                     ENTITYID)
           VALUES (pCORRELATIONID,
                   SYS_EXTRACT_UTC (SYSTIMESTAMP),
                   xmlText,
                   v_crm_attr_queue_out,
                   v_attr_send_request_service_name,
                   pFB_BSC_DOCID);

      COMMIT;
   END;

   PROCEDURE INSERT_ATTR_MEMBER_RESPONSE (pRESPONSE        IN CLOB,
                                          pCORRELATIONID   IN VARCHAR2,
                                          pFB_BSC_DOCID    IN CHAR)
   IS
   BEGIN
      INSERT INTO NM_CRM.FB_BSC_LOG (CORRELATION_ID,
                                     CREATEDATE,
                                     XML_TEXT,
                                     QUEUE_NAME,
                                     SERVICE_NAME,
                                     ENTITYID)
           VALUES (pCORRELATIONID,
                   SYS_EXTRACT_UTC (SYSTIMESTAMP),
                   pRESPONSE,
                   v_crm_attr_queue_in,
                   v_crm_send_reponse_service_name,
                   pFB_BSC_DOCID);


      MERGE INTO SYSDBA.FB_BSC_DOC_CHECK BDC
           USING (            SELECT BDC.*,
                                     (              SELECT JSON_ARRAYAGG (DESICIONINFOVALUE)
                                                      FROM XMLTABLE (
                                                              '/DecisionInfo'
                                                              PASSING BDC.DESICIONINFOXML
                                                              COLUMNS DESICIONINFOVALUE   VARCHAR (1024)
                                                                                             PATH 'text()'))
                                        AS DESICIONINFO
                                FROM XMLTABLE (
                                        '/Response'
                                        PASSING XMLTYPE (pRESPONSE)
                                        COLUMNS RESULTTYPE        VARCHAR2 (128)
                                                                     PATH 'ResultInfo/ResultType',
                                                TRANSID           VARCHAR2 (64)
                                                                     PATH 'DataBlock/Application/TransId',
                                                REQUESTID         VARCHAR2 (64)
                                                                     PATH 'DataBlock/Application/RequestId',
                                                EXTCLIENTID       CHAR (12)
                                                                     PATH 'DataBlock/LegalPerson/ExtClientId',
                                                DESICIONINFOXML   XMLTYPE
                                                                     PATH 'DataBlock/Application/Decision/DecisionInfo',
                                                DESICIONNAME      VARCHAR2 (256)
                                                                     PATH 'DataBlock/Application/Decision/DecisionName',
                                                DESICIONTYPE      NUMBER
                                                                     PATH 'DataBlock/Application/Decision/DecisionType',
                                                ERRORCODE         NUMBER
                                                                     PATH 'ResultInfo/ErrorInfo/Code') BDC)
                 RBDC
              ON (    BDC.TRANSID = RBDC.TRANSID
                  AND BDC.REQUESTID = RBDC.REQUESTID
                  AND BDC.ACCOUNTID = RBDC.EXTCLIENTID
                  AND BDC.FB_BSC_DOCID = pFB_BSC_DOCID)
      WHEN MATCHED
      THEN
         UPDATE SET
            BDC.DESICIONTYPE =
               CASE
                  WHEN LOWER (RBDC.RESULTTYPE) = 'ok' THEN RBDC.DESICIONTYPE
                  ELSE BDC.DESICIONTYPE
               END,
            BDC.CHECKCOMMENT =
               CASE
                  WHEN LOWER (RBDC.RESULTTYPE) = 'ok'
                  THEN
                     TO_CLOB (RBDC.DESICIONINFO)
                  ELSE
                     TO_CLOB (BDC.CHECKCOMMENT)
               END,
            BDC.CODEERROR =
               CASE
                  WHEN LOWER (RBDC.RESULTTYPE) = 'error' THEN RBDC.ERRORCODE
                  ELSE BDC.CODEERROR
               END,
            BDC.DESICIONNAME = RBDC.DESICIONNAME;
   END;

   PROCEDURE GENERATE_ATTR_CHECK_FINAL_RESULT (
      pORDER_DECISION_TYPE         IN     NUMBER,
      pEXECUTOR_DECISION_TYPE      IN     NUMBER,
      pNEED_TO_SKIP_CHECK_ORDER    IN     CHAR,
      pFINAL_DOC_STATUS               OUT VARCHAR2,
      pFINAL_DOC_STATUS_REASON        OUT VARCHAR2,
      pIS_RESULT_CONDITIONAL_POS      OUT CHAR)
   IS
   BEGIN
      pIS_RESULT_CONDITIONAL_POS := 'F';
      pFINAL_DOC_STATUS := 'MEMBER_CHECK_ERR';
      pFINAL_DOC_STATUS_REASON :=
         'Не удалось определить статус после проверки участников';

      IF (pNEED_TO_SKIP_CHECK_ORDER = 'T')
      THEN
         IF (pEXECUTOR_DECISION_TYPE IS NULL)
         THEN
            pFINAL_DOC_STATUS := 'MEMBER_CHECK_ERR';
            pFINAL_DOC_STATUS_REASON := 'Timeout';
         ELSIF (pEXECUTOR_DECISION_TYPE = 1)
         THEN
            pFINAL_DOC_STATUS := 'MEMBER_CHECK_ERR';
            pFINAL_DOC_STATUS_REASON :=
               'Ошибка проверки участников';
         ELSIF (pEXECUTOR_DECISION_TYPE = 2)
         THEN
            pFINAL_DOC_STATUS := 'MEMBER_CHECK_NEG';
            pFINAL_DOC_STATUS_REASON :=
               'Отрицательный результат проверки участников';
         ELSIF (pEXECUTOR_DECISION_TYPE = 0)
         THEN
            pFINAL_DOC_STATUS := 'MEMBER_CHECK_POS';
            pFINAL_DOC_STATUS_REASON :=
               'Положительный результат проверки участников';
         ELSIF (pEXECUTOR_DECISION_TYPE = 3)
         THEN
            pFINAL_DOC_STATUS := 'MEMBER_CHECK_POS';
            pFINAL_DOC_STATUS_REASON :=
               'Условно-положительный результат проверки участников';
            pIS_RESULT_CONDITIONAL_POS := 'T';
         END IF;
      ELSE
         IF (pORDER_DECISION_TYPE = 2 OR pEXECUTOR_DECISION_TYPE = 2)
         THEN
            pFINAL_DOC_STATUS := 'MEMBER_CHECK_NEG';
            pFINAL_DOC_STATUS_REASON :=
               'Отрицательный результат проверки участников';
         ELSIF (   pORDER_DECISION_TYPE IS NULL
                OR pEXECUTOR_DECISION_TYPE IS NULL)
         THEN
            pFINAL_DOC_STATUS := 'MEMBER_CHECK_ERR';
            pFINAL_DOC_STATUS_REASON := 'Timeout';
         ELSIF (pORDER_DECISION_TYPE = 1 OR pEXECUTOR_DECISION_TYPE = 1)
         THEN
            pFINAL_DOC_STATUS := 'MEMBER_CHECK_ERR';
            pFINAL_DOC_STATUS_REASON :=
               'Ошибка проверки участников';
         ELSIF (pORDER_DECISION_TYPE = 3 OR pEXECUTOR_DECISION_TYPE = 3)
         THEN
            pFINAL_DOC_STATUS := 'MEMBER_CHECK_POS';
            pFINAL_DOC_STATUS_REASON :=
               'Условно-положительный результат проверки участников';
            pIS_RESULT_CONDITIONAL_POS := 'T';
         ELSIF (pORDER_DECISION_TYPE = 0 AND pEXECUTOR_DECISION_TYPE = 0)
         THEN
            pFINAL_DOC_STATUS := 'MEMBER_CHECK_POS';
            pFINAL_DOC_STATUS_REASON :=
               'Положительный результат проверки участников';
         END IF;
      END IF;
   END;

   PROCEDURE SEND_DOC_TO_ATTR_P (pFB_BSC_DOCID IN CHAR, pUSERID IN CHAR)
   IS
      v_outmsg_id                             RAW (16);
      v_fulloutmsg                            CLOB;
      v_correlation_id_order                  VARCHAR2 (32) := '123'; -- SYS_GUID ();
      v_response_order                        CLOB;
      v_response_order_exception_msg          VARCHAR2 (256);
      v_response_order_decision_type          NUMBER (4) := NULL;
      v_correlation_id_executor               VARCHAR2 (32) := '124'; -- SYS_GUID ();
      v_response_executor                     CLOB;
      v_response_executor_exception_msg       VARCHAR2 (256);
      v_response_executor_decision_type       NUMBER (4) := NULL;
      v_executor_check                        SYSDBA.FB_BSC_DOC_CHECK%ROWTYPE;
      v_timer1                                NUMBER (12);
      v_timer2                                NUMBER (12);
      v_domain                                VARCHAR2 (128);
      v_user_email                            VARCHAR2 (300);
      v_expiration_time                       NUMBER (12);
      v_bsc_doc                               SYSDBA.FB_BSC_DOC%ROWTYPE;
      v_bsc_doc_url                           VARCHAR2 (256);
      v_bsc_doc_final_doc_status              VARCHAR2 (128);
      v_bsc_doc_final_status_reason           VARCHAR2 (1200);
      v_is_final_doc_status_conditional_pos   CHAR (1);
      v_error_msg                             VARCHAR2 (512);
      v_executor_title                        VARCHAR2 (128);
      v_executor_inn                          VARCHAR2 (12);
      v_need_to_skip_check_order              CHAR (1) := 'F';
   BEGIN
      -- Получаем время ожидания из пользовательских настроек
      BEGIN
         SELECT TO_NUMBER (DATAVALUE,
                           'FM99999999999999999D9999',
                           'nls_numeric_characters = ''. ''')
           INTO v_expiration_time
           FROM SYSDBA.CUSTOMSETTINGS
          WHERE     CATEGORY = 'Bank Support Contract'
                AND DESCRIPTION = 'BSC_Contraparty_Check_Timeout';
      EXCEPTION
         WHEN OTHERS
         THEN
            v_expiration_time := NULL;
      END;

      -- Получить данные текущего документа
      SELECT *
        INTO v_bsc_doc
        FROM SYSDBA.FB_BSC_DOC
       WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

      -- Получаем домен для емайлов
      BEGIN
         SELECT DATAVALUE
           INTO v_domain
           FROM SYSDBA.CUSTOMSETTINGS
          WHERE CATEGORY = 'InforCRMHyperLink' AND ROWNUM = 1;
      EXCEPTION
         WHEN OTHERS
         THEN
            v_domain := NULL;
      END;

      -- Получаем информацию об исполнителе
      BEGIN
         SELECT ACCOUNT, INN
           INTO v_executor_title, v_executor_inn
           FROM SYSDBA.ACCOUNT
          WHERE ACCOUNTID = v_bsc_doc.EXECUTORID;
      EXCEPTION
         WHEN OTHERS
         THEN
            v_executor_title := NULL;
            v_executor_inn := NULL;
      END;

      v_bsc_doc_url :=
            v_domain
         || 'FbBscDoc.aspx?entityid='
         || v_bsc_doc.FB_BSC_DOCID
         || '&'
         || 'modeid=detail';

      -- Получить email текущего пользователя
      BEGIN
         SELECT EMAIL
           INTO v_user_email
           FROM SYSDBA.V_FB_WORKER
          WHERE USERID = pUSERID;
      EXCEPTION
         WHEN OTHERS
         THEN
            v_user_email := '';
      END;

      COMMIT;

      v_need_to_skip_check_order :=
         CASE
            WHEN (   v_bsc_doc.ISNONEORDER = 'T'
                  OR v_bsc_doc.BSC_DOC_TYPE IN ('ARTICLE', 'ARTICLE_PROJ'))
            THEN
               'T'
            ELSE
               'F'
         END;

      SEND_MEMBER_TO_ATTR (0,
                           v_bsc_doc.ORDERID,
                           pFB_BSC_DOCID,
                           pUSERID,
                           v_correlation_id_order,
                           v_need_to_skip_check_order);

      SEND_MEMBER_TO_ATTR (1,
                           v_bsc_doc.EXECUTORID,
                           pFB_BSC_DOCID,
                           pUSERID,
                           v_correlation_id_executor,
                           v_need_to_skip_check_order);

      v_timer1 := DBMS_UTILITY.get_time ();

      LOOP
         v_timer2 := DBMS_UTILITY.get_time ();
         EXIT WHEN (   (ABS (v_timer1 - v_timer2) / 100) > v_expiration_time
                    OR (    (   v_response_order IS NOT NULL
                             OR v_need_to_skip_check_order = 'T')
                        AND v_response_executor IS NOT NULL));

         IF (v_response_order IS NULL AND v_need_to_skip_check_order = 'F')
         THEN
            NM_CRM.fb_listen_queue (v_crm_attr_queue_in,
                                    NULL,
                                    v_correlation_id_order,
                                    v_response_order,
                                    v_response_order_exception_msg);
         END IF;

         IF (v_response_executor IS NULL)
         THEN
            NM_CRM.fb_listen_queue (v_crm_attr_queue_in,
                                    NULL,
                                    v_correlation_id_executor,
                                    v_response_executor,
                                    v_response_executor_exception_msg);
         END IF;
      END LOOP;

      IF (v_response_order IS NOT NULL AND v_need_to_skip_check_order = 'F')
      THEN
         INSERT_ATTR_MEMBER_RESPONSE (v_response_order,
                                      v_correlation_id_order,
                                      pFB_BSC_DOCID);

                  SELECT BDC.DESICIONTYPE
                    INTO v_response_order_decision_type
                    FROM XMLTABLE (
                            '/Response'
                            PASSING XMLTYPE (v_response_order)
                            COLUMNS DESICIONTYPE   NUMBER
                                                      PATH 'DataBlock/Application/Decision/DecisionType') BDC;
      END IF;

      IF (v_response_executor IS NOT NULL)
      THEN
         INSERT_ATTR_MEMBER_RESPONSE (v_response_executor,
                                      v_correlation_id_executor,
                                      pFB_BSC_DOCID);

                  SELECT BDC.DESICIONTYPE
                    INTO v_response_executor_decision_type
                    FROM XMLTABLE (
                            '/Response'
                            PASSING XMLTYPE (v_response_executor)
                            COLUMNS DESICIONTYPE   NUMBER
                                                      PATH 'DataBlock/Application/Decision/DecisionType') BDC;
      END IF;

      COMMIT;

      GENERATE_ATTR_CHECK_FINAL_RESULT (
         v_response_order_decision_type,
         v_response_executor_decision_type,
         v_need_to_skip_check_order,
         v_bsc_doc_final_doc_status,
         v_bsc_doc_final_status_reason,
         v_is_final_doc_status_conditional_pos);

      UPDATE SYSDBA.FB_BSC_DOC
         SET DOC_STATUS = v_bsc_doc_final_doc_status,
             DOC_STATUS_REASON = v_bsc_doc_final_status_reason
       WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

      COMMIT;

      IF (v_bsc_doc_final_doc_status = 'MEMBER_CHECK_ERR')
      THEN
         NM_CRM.BSC_PKG.SEND_EMAIL (
               'Ошибка проверки участников '
            || NM_CRM.BSC_PKG.MAP_BSCDOCTYPE_TO_TEXT_GENETIVE (
                  v_bsc_doc.BSC_DOC_TYPE)
            || CASE
                  WHEN v_bsc_doc.BSC_DOC_TYPE IN ('EXPENSE_SHEET',
                                                  'ARTICLE',
                                                  'ARTICLE_PROJ')
                  THEN
                     '. Клиент'
                  ELSE
                        '. Исполнитель по '
                     || NM_CRM.BSC_PKG.MAP_BSCDOCTYPE_TO_TEXT_DATIVE (
                           v_bsc_doc.BSC_DOC_TYPE)
               END
            || ': '
            || v_executor_title
            || ' '
            || v_executor_inn,
               '<p>В результате проверки участников в <a href="'
            || v_bsc_doc_url
            || '">'
            || (v_bsc_doc.BSCDOCTYPETEXT || ' ' || v_bsc_doc.DOCNUMBER)
            || ' от '
            || TO_CHAR (v_bsc_doc.DOCSTARTDATE, 'dd.MM.yyyy')
            || '</a> возникли ошибки проверки. Требуется повторная проверка. (инициализация запуска проверки в ручном режиме)</p>',
            v_user_email);
      ELSIF (    v_bsc_doc_final_doc_status = 'MEMBER_CHECK_POS'
             AND v_is_final_doc_status_conditional_pos = 'F')
      THEN
         NM_CRM.BSC_PKG.SEND_EMAIL (
               'Проверка участников '
            || NM_CRM.BSC_PKG.MAP_BSCDOCTYPE_TO_TEXT_GENETIVE (
                  v_bsc_doc.BSC_DOC_TYPE)
            || ' завершена положительно'
            || CASE
                  WHEN v_bsc_doc.BSC_DOC_TYPE IN ('EXPENSE_SHEET',
                                                  'ARTICLE',
                                                  'ARTICLE_PROJ')
                  THEN
                     '. Клиент'
                  ELSE
                        '. Исполнитель по '
                     || NM_CRM.BSC_PKG.MAP_BSCDOCTYPE_TO_TEXT_DATIVE (
                           v_bsc_doc.BSC_DOC_TYPE)
               END
            || ': '
            || v_executor_title
            || ' '
            || v_executor_inn,
               '<p>Проверка участников в <a href="'
            || v_bsc_doc_url
            || '">'
            || (v_bsc_doc.BSCDOCTYPETEXT || ' ' || v_bsc_doc.DOCNUMBER)
            || ' от '
            || TO_CHAR (v_bsc_doc.DOCSTARTDATE, 'dd.MM.yyyy')
            || '</a> завершена положительно. Рекомендуется дальнейшее согласование.</p>',
            v_user_email);
      ELSIF (    v_bsc_doc_final_doc_status = 'MEMBER_CHECK_POS'
             AND v_is_final_doc_status_conditional_pos = 'T')
      THEN
         NM_CRM.BSC_PKG.SEND_EMAIL (
               'Проверка участников '
            || NM_CRM.BSC_PKG.MAP_BSCDOCTYPE_TO_TEXT_GENETIVE (
                  v_bsc_doc.BSC_DOC_TYPE)
            || ' завершена успешно'
            || CASE
                  WHEN v_bsc_doc.BSC_DOC_TYPE IN ('EXPENSE_SHEET',
                                                  'ARTICLE',
                                                  'ARTICLE_PROJ')
                  THEN
                     '. Клиент'
                  ELSE
                        '. Исполнитель по '
                     || NM_CRM.BSC_PKG.MAP_BSCDOCTYPE_TO_TEXT_DATIVE (
                           v_bsc_doc.BSC_DOC_TYPE)
               END
            || ': '
            || v_executor_title
            || ' '
            || v_executor_inn,
               '<p>Проверка участников в <a href="'
            || v_bsc_doc_url
            || '">'
            || (v_bsc_doc.BSCDOCTYPETEXT || ' ' || v_bsc_doc.DOCNUMBER)
            || ' от '
            || TO_CHAR (v_bsc_doc.DOCSTARTDATE, 'dd.MM.yyyy')
            || '</a> завершена. Имеются стоп-факторы, влияющие на результат согласования.</p><p>Рекомендуется дальнейшее согласование.</p>',
            v_user_email);
      ELSIF (v_bsc_doc_final_doc_status = 'MEMBER_CHECK_NEG')
      THEN
         NM_CRM.BSC_PKG.SEND_EMAIL (
               'Проверка участников '
            || NM_CRM.BSC_PKG.MAP_BSCDOCTYPE_TO_TEXT_GENETIVE (
                  v_bsc_doc.BSC_DOC_TYPE)
            || ' завершена отрицательно'
            || CASE
                  WHEN v_bsc_doc.BSC_DOC_TYPE IN ('EXPENSE_SHEET',
                                                  'ARTICLE',
                                                  'ARTICLE_PROJ')
                  THEN
                     '. Клиент'
                  ELSE
                        '. Исполнитель по '
                     || NM_CRM.BSC_PKG.MAP_BSCDOCTYPE_TO_TEXT_DATIVE (
                           v_bsc_doc.BSC_DOC_TYPE)
               END
            || ': '
            || v_executor_title
            || ' '
            || v_executor_inn,
               '<p>Проверка участников в <a href="'
            || v_bsc_doc_url
            || '">'
            || (v_bsc_doc.BSCDOCTYPETEXT || ' ' || v_bsc_doc.DOCNUMBER)
            || ' от '
            || TO_CHAR (v_bsc_doc.DOCSTARTDATE, 'dd.MM.yyyy')
            || '</a> завершена отрицательно.</p><p>Рекомендуется прекращение согласования.</p><p>Направить клиенту '
            || '<a href="'
            || v_domain
            || 'Account.aspx?entityid='
            || v_bsc_doc.EXECUTORID
            || '&'
            || 'modeid=detail'
            || '">'
            || v_executor_title
            || '</a> сообщение следующего содержания:'
            || '</p><q><p>Уважаемый '
            || v_executor_title
            || '!</p>'
            || '<p>Благодарим Вас за выбор нашего банка!</p>'
            || '<p>К сожалению, вынуждены сообщить, что согласовать возможность принятия контракта на сопровождение не представляется возможным в связи с возникновением препятствий законодательного характера.</p></q>',
            v_user_email);
      END IF;

      COMMIT;
   EXCEPTION
      WHEN OTHERS
      THEN
         v_error_msg := SQLERRM;

         INSERT INTO NM_CRM.FB_BSC_LOG (CORRELATION_ID,
                                        CREATEDATE,
                                        XML_TEXT,
                                        QUEUE_NAME,
                                        SERVICE_NAME,
                                        ENTITYID,
                                        EXCEPTION_MSG)
              VALUES (v_correlation_id_order,
                      SYS_EXTRACT_UTC (SYSTIMESTAMP),
                      v_response_order,
                      v_crm_attr_queue_in,
                      'Exception',
                      pFB_BSC_DOCID,
                      v_error_msg);

         INSERT INTO NM_CRM.FB_BSC_LOG (CORRELATION_ID,
                                        CREATEDATE,
                                        XML_TEXT,
                                        QUEUE_NAME,
                                        SERVICE_NAME,
                                        ENTITYID,
                                        EXCEPTION_MSG)
              VALUES (v_correlation_id_executor,
                      SYS_EXTRACT_UTC (SYSTIMESTAMP),
                      v_response_executor,
                      v_crm_attr_queue_in,
                      'Exception',
                      pFB_BSC_DOCID,
                      v_error_msg);

         COMMIT;
   END;

   PROCEDURE SEND_DOC_TO_ATTR (pFB_BSC_DOCID IN CHAR, pUSERID IN CHAR)
   IS
   BEGIN
      DBMS_SCHEDULER.create_job (
         job_name     => 'NM_CRM.FB_BSC_SEND_DOC_TO_ATTR_JOB_' || pFB_BSC_DOCID,
         job_type     => 'PLSQL_BLOCK',
         job_action   =>    'begin NM_CRM.BSC_PKG.SEND_DOC_TO_ATTR_P('''
                         || pFB_BSC_DOCID
                         || ''', '''
                         || pUSERID
                         || '''); end;',
         start_date   => SYSDATE,
         enabled      => TRUE,
         auto_drop    => TRUE,
         comments     => 'one-time job');
   EXCEPTION
      WHEN OTHERS
      THEN
         NULL;
   END;

   PROCEDURE SEND_DOC_TO_APPROVE (pFB_BSC_DOCID    IN     CHAR,
                                  pEXCEPTION_MSG      OUT VARCHAR2)
   IS
      v_outmsg_id                RAW (16);
      v_fulloutmsg               CLOB;
      executor_inn               VARCHAR2 (64);
      order_inn                  VARCHAR2 (64);
      bsc_doc                    SYSDBA.FB_BSC_DOC%ROWTYPE;
      v_correlation_id           VARCHAR2 (32) := '123';        --SYS_GUID ();
      v_response                 CLOB;
      v_response_exception_msg   VARCHAR2 (512);
      v_error_msg                VARCHAR2 (512);
      v_expiration_time          NUMBER (12);
      v_response_error_reason    VARCHAR2 (64);
   BEGIN
      -- Получаем данные о текущем документе
      SELECT BD.*
        INTO bsc_doc
        FROM SYSDBA.FB_BSC_DOC BD
       WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

      -- Меняем статус на Передеча в GD
      UPDATE SYSDBA.FB_BSC_DOC
         SET DOC_STATUS = 'DOC_TO_GD',
             DOC_STATUS_REASON =
                'Направление карточки в GreenData'
       WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

      COMMIT;

      -- Получаем время ожидания из пользовательских настроек
      BEGIN
         SELECT TO_NUMBER (DATAVALUE,
                           'FM99999999999999999D9999',
                           'nls_numeric_characters = ''. ''')
           INTO v_expiration_time
           FROM SYSDBA.CUSTOMSETTINGS
          WHERE     CATEGORY = 'Bank Support Contract'
                AND DESCRIPTION = 'BSC_Contraparty_GD_Check_Timeout';
      EXCEPTION
         WHEN OTHERS
         THEN
            v_expiration_time := NULL;
      END;

      -- Получаем ИНН заказчика и исполнителя
      BEGIN
         SELECT INN
           INTO executor_inn
           FROM SYSDBA.ACCOUNT
          WHERE ACCOUNTID = bsc_doc.EXECUTORID;
      EXCEPTION
         WHEN OTHERS
         THEN
            executor_inn := NULL;
      END;

      BEGIN
         SELECT INN
           INTO order_inn
           FROM SYSDBA.ACCOUNT
          WHERE ACCOUNTID = bsc_doc.ORDERID;
      EXCEPTION
         WHEN OTHERS
         THEN
            order_inn := NULL;
      END;


      IF (    executor_inn IS NOT NULL
          AND order_inn IS NOT NULL
          AND executor_inn = order_inn)
      THEN
         UPDATE SYSDBA.FB_BSC_DOC
            SET DOC_STATUS = 'DOC_TO_GD_ERR',
                DOC_STATUS_REASON =
                   'Заказчик совпадает с исполнителем'
          WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

         COMMIT;

         UPDATE SYSDBA.FB_BSC_DOC
            SET DOC_STATUS = 'MEMBER_CHECK_POS'
          WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

         COMMIT;
         pEXCEPTION_MSG :=
            'ИНН заказчика и исполнителя совпадают!';
         RETURN;
      END IF;

      -- Формируем XML
      SELECT NM_CRM.BSC_PKG.MAP_DOC_TO_XML_GD (pFB_BSC_DOCID,
                                               v_correlation_id)
        INTO v_fulloutmsg
        FROM DUAL;

      -- Отправляем XML
      NM_CRM.BSC_PKG.ENQUEUE_MESSAGE (v_fulloutmsg,
                                      v_gd_send_document_service_name,
                                      v_correlation_id,
                                      v_crm_gd_queue_out,
                                      v_outmsg_id);

      -- Пишем в лог XML которую отправляем
      INSERT INTO NM_CRM.FB_BSC_LOG (CORRELATION_ID,
                                     CREATEDATE,
                                     XML_TEXT,
                                     QUEUE_NAME,
                                     SERVICE_NAME,
                                     ENTITYID)
           VALUES (v_correlation_id,
                   SYS_EXTRACT_UTC (SYSTIMESTAMP),
                   v_fulloutmsg,
                   v_crm_gd_queue_out,
                   v_gd_send_document_service_name,
                   pFB_BSC_DOCID);

      COMMIT;

      NM_CRM.fb_listen_queue (v_crm_gd_queue_in,
                              v_expiration_time,
                              v_correlation_id,
                              v_response,
                              v_response_exception_msg);

      -- Если вышло время ожидания ответа
      IF (v_response_exception_msg = 'no_message')
      THEN
         UPDATE SYSDBA.FB_BSC_DOC
            SET DOC_STATUS = 'DOC_TO_GD_ERR',
                DOC_STATUS_REASON =
                   'Вышло время ожидания ответа от GreenData'
          WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

         COMMIT;

         UPDATE SYSDBA.FB_BSC_DOC
            SET DOC_STATUS = 'MEMBER_CHECK_POS'
          WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

         COMMIT;
         pEXCEPTION_MSG :=
            'Невозможно добавить карточку документа. Вышло время ожидания ответа!';
         RETURN;
      END IF;

      -- Пишем в лог XML которой ответили GD
      INSERT INTO NM_CRM.FB_BSC_LOG (CORRELATION_ID,
                                     CREATEDATE,
                                     XML_TEXT,
                                     QUEUE_NAME,
                                     SERVICE_NAME,
                                     ENTITYID)
           VALUES (v_correlation_id,
                   SYS_EXTRACT_UTC (SYSTIMESTAMP),
                   v_response,
                   v_crm_gd_queue_in,
                   v_crm_send_reponse_service_name,
                   pFB_BSC_DOCID);

      COMMIT;

      FOR responseEntity
         IN (     SELECT RESP.*
                    FROM XMLTABLE (
                            '/OpenAPI/Message/Object/Response'
                            PASSING XMLTYPE (v_response)
                            COLUMNS CRM_ID     VARCHAR2 (12) PATH 'CRM_ID',
                                    GD_ID      INTEGER PATH 'GD_ID',
                                    MSG_CODE   INTEGER PATH 'MESSAGE_CODE',
                                    MSG        VARCHAR2 (128) PATH 'MESSAGE') RESP)
      LOOP
         IF (responseEntity.MSG_CODE = 0)
         THEN
            UPDATE SYSDBA.FB_BSC_DOC
               SET DOC_STATUS = 'ON_FILLING',
                   BSC_GREENDATA_DOC_ID = responseEntity.GD_ID,
                   DOC_STATUS_REASON =
                      'Получен статус из GreenData'
             WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

            COMMIT;
         ELSIF (responseEntity.MSG_CODE = 2)
         THEN
            UPDATE SYSDBA.FB_BSC_DOC
               SET DOC_STATUS = responseEntity.MSG,
                   BSC_GREENDATA_DOC_ID = responseEntity.GD_ID,
                   DOC_STATUS_REASON =
                      'Карточка уже создана на стороне GreenData'
             WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

            COMMIT;

            pEXCEPTION_MSG :=
                  'Карточка уже создана на стороне GreenData. Текущий статус: '
               || TRANSLATE_VALUE_BY_DICTIONARY (
                     responseEntity.MSG,
                     'Статус Карточки документа БСК');
         ELSE
            v_response_error_reason :=
               CASE
                  WHEN responseEntity.MSG_CODE = 1
                  THEN
                     'Получен неопознанный тип документа.'
                  WHEN responseEntity.MSG_CODE = 3
                  THEN
                     'Ошибка обновления Клиента.'
                  WHEN responseEntity.MSG_CODE = 4
                  THEN
                     'Ошибка создания документа.'
                  WHEN responseEntity.MSG_CODE = 5
                  THEN
                     'Ошибка: предыдущая версия документа на согласовании.'
                  WHEN responseEntity.MSG_CODE = 6
                  THEN
                     'Ошибка валидации данных.'
                  WHEN responseEntity.MSG_CODE = 8
                  THEN
                     'Не найден связанный объект.'
                  WHEN responseEntity.MSG_CODE = 500
                  THEN
                     'Непредвиденная ошибка.'
                  ELSE
                     'Получен неопознанный тип запроса.'
               END;

            UPDATE SYSDBA.FB_BSC_DOC
               SET DOC_STATUS = 'DOC_TO_GD_ERR',
                   DOC_STATUS_REASON = v_response_error_reason,
                   BSC_GREENDATA_DOC_ID = responseEntity.GD_ID
             WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

            COMMIT;

            UPDATE SYSDBA.FB_BSC_DOC
               SET DOC_STATUS = 'MEMBER_CHECK_POS',
                   DOC_STATUS_REASON = v_response_error_reason
             WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

            COMMIT;

            pEXCEPTION_MSG :=
                  v_response_error_reason
               || ' Обратитесь к администратору. '
               || responseEntity.MSG;
         END IF;
      END LOOP;

      COMMIT;
   EXCEPTION
      WHEN OTHERS
      THEN
         v_error_msg := SQLERRM;

         INSERT INTO NM_CRM.FB_BSC_LOG (CORRELATION_ID,
                                        CREATEDATE,
                                        XML_TEXT,
                                        QUEUE_NAME,
                                        SERVICE_NAME,
                                        ENTITYID,
                                        EXCEPTION_MSG)
              VALUES (v_correlation_id,
                      SYS_EXTRACT_UTC (SYSTIMESTAMP),
                      v_response,
                      v_crm_gd_queue_in,
                      'Exception',
                      pFB_BSC_DOCID,
                      v_error_msg);

         COMMIT;
   END;

   PROCEDURE SEND_DOC_STATUS_TO_GD (
      pFB_BSC_DOCID             IN     CHAR,
      pCORRELATIONID            IN     VARCHAR2,
      pINITIAL_DOC_STATUS       IN     VARCHAR2,
      pUSERID                   IN     CHAR,
      pBSC_DOC_URL              IN     VARCHAR2,
      pTRY_TO_REAPPROVE_COUNT   IN     INTEGER,
      pRESPONSE_MSG                OUT VARCHAR2)
   IS
      v_outmsg_id               RAW (16);
      v_fulloutmsg              CLOB;
      v_resp_msg                CLOB;
      v_out_exception_msg       VARCHAR2 (256);
      v_response_crm_id         VARCHAR2 (12);
      v_response_gd_id          INTEGER;
      v_response_message        VARCHAR2 (256);
      v_response_message_code   INTEGER;
      v_bsc_doc                 SYSDBA.FB_BSC_DOC%ROWTYPE;
      v_user_email              VARCHAR2 (300);
      v_need_to_drop_jobs       CHAR (1) := 'T';
      v_error_msg               VARCHAR2 (512);
      v_expiration_time         NUMBER (12);
   BEGIN
      UPDATE SYSDBA.FB_BSC_DOC
         SET DOC_STATUS = pINITIAL_DOC_STATUS
       WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

      COMMIT;

      UPDATE SYSDBA.FB_BSC_DOC
         SET DOC_STATUS = 'STATUS_TO_GD',
             DOC_STATUS_REASON =
                'Направление карточки в GreenData'
       WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

      COMMIT;

      -- Формирование XML
      SELECT NM_CRM.BSC_PKG.FORM_DOC_STATUS_RESPONSE_MESSAGE (
                pFB_BSC_DOCID,
                pINITIAL_DOC_STATUS,
                pCORRELATIONID)
        INTO v_fulloutmsg
        FROM DUAL;


      -- Получаем время ожидания из пользовательских настроек
      BEGIN
         SELECT TO_NUMBER (DATAVALUE,
                           'FM99999999999999999D9999',
                           'nls_numeric_characters = ''. ''')
           INTO v_expiration_time
           FROM SYSDBA.CUSTOMSETTINGS
          WHERE     CATEGORY = 'Bank Support Contract'
                AND DESCRIPTION = 'BSC_Contraparty_GD_Check_Timeout';
      EXCEPTION
         WHEN OTHERS
         THEN
            v_expiration_time := NULL;
      END;

      -- Получить данные текущего документа
      SELECT *
        INTO v_bsc_doc
        FROM SYSDBA.FB_BSC_DOC
       WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

      -- Отправка XML
      NM_CRM.BSC_PKG.ENQUEUE_MESSAGE (v_fulloutmsg,
                                      v_gd_send_status_service_name,
                                      pCORRELATIONID,
                                      v_crm_gd_queue_out,
                                      v_outmsg_id);

      INSERT INTO NM_CRM.FB_BSC_LOG (CORRELATION_ID,
                                     CREATEDATE,
                                     XML_TEXT,
                                     QUEUE_NAME,
                                     SERVICE_NAME,
                                     ENTITYID)
           VALUES (pCORRELATIONID,
                   SYS_EXTRACT_UTC (SYSTIMESTAMP),
                   v_fulloutmsg,
                   v_crm_gd_queue_out,
                   v_gd_send_status_service_name,
                   pFB_BSC_DOCID);

      COMMIT;

      -- Получить email текущего пользователя
      BEGIN
         SELECT EMAIL
           INTO v_user_email
           FROM SYSDBA.V_FB_WORKER
          WHERE USERID = pUSERID;
      EXCEPTION
         WHEN OTHERS
         THEN
            v_user_email := NULL;
      END;

      -- Чтение очереди для обработки ответа
      NM_CRM.fb_listen_queue (v_crm_gd_queue_in,
                              v_expiration_time,
                              pCORRELATIONID,
                              v_resp_msg,
                              v_out_exception_msg);

      -- Если ответ не пришел спустя время ожидания
      IF (v_out_exception_msg = 'no_message')
      THEN
         UPDATE SYSDBA.FB_BSC_DOC
            SET DOC_STATUS = 'STATUS_TO_GD_ERR',
                DOC_STATUS_REASON =
                   'Вышло время ожидания ответа от GreenData'
          WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

         COMMIT;

         UPDATE SYSDBA.FB_BSC_DOC
            SET DOC_STATUS = 'DISAPPROVAL'
          WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

         COMMIT;

         pRESPONSE_MSG :=
            'Невозможно изменить статус документа. Вышло время ожидания ответа!';

         IF (pINITIAL_DOC_STATUS = 'CRM_CONFIRM')
         THEN
            -- Джоб на повторные попытки отправки каждые 30 минут 10 раз
            IF (pTRY_TO_REAPPROVE_COUNT = 0)
            THEN
               FOR jobCounter IN 1 .. 10
               LOOP
                  DBMS_SCHEDULER.CREATE_JOB (
                     JOB_NAME     =>    'FB_BSC_REAPPROVE_DOC_STATUS_JOB_'
                                     || pFB_BSC_DOCID
                                     || '_'
                                     || jobCounter,
                     JOB_TYPE     => 'PLSQL_BLOCK',
                     JOB_ACTION   =>    '
                    DECLARE
                        pRESPONSE_MSG VARCHAR2(256);
                    BEGIN
                        NM_CRM.BSC_PKG.SEND_DOC_STATUS_TO_GD('''
                                     || pFB_BSC_DOCID
                                     || ''', '''
                                     || pCORRELATIONID
                                     || ''', '''
                                     || pINITIAL_DOC_STATUS
                                     || ''', '''
                                     || pUSERID
                                     || ''', '''
                                     || pBSC_DOC_URL
                                     || ''', '
                                     || jobCounter
                                     || ', pRESPONSE_MSG);
                    END;',
                     START_DATE   =>   SYSTIMESTAMP
                                     + ( (INTERVAL '30' MINUTE) * jobCounter),
                     COMMENTS     => 'Reapprove bsc doc status',
                     ENABLED      => TRUE,
                     AUTO_DROP    => TRUE);
               END LOOP;
            END IF;

            v_need_to_drop_jobs := 'F';
         END IF;
      ELSE                                                -- Если ответ пришел
         -- Пишем в лог
         INSERT INTO NM_CRM.FB_BSC_LOG (CORRELATION_ID,
                                        CREATEDATE,
                                        XML_TEXT,
                                        QUEUE_NAME,
                                        SERVICE_NAME,
                                        ENTITYID,
                                        EXCEPTION_MSG)
              VALUES (pCORRELATIONID,
                      SYS_EXTRACT_UTC (SYSTIMESTAMP),
                      v_resp_msg,
                      v_crm_gd_queue_in,
                      v_crm_send_reponse_service_name,
                      pFB_BSC_DOCID,
                      v_out_exception_msg);

         COMMIT;

                           SELECT XT.CRM_ID,
                                  XT.GD_ID,
                                  XT.RESPONSE_MESSAGE,
                                  XT.RESPONSE_MESSAGE_CODE
                             INTO v_response_crm_id,
                                  v_response_gd_id,
                                  v_response_message,
                                  v_response_message_code
                             FROM XMLTABLE (
                                     'OpenAPI/Message/Object/Response'
                                     PASSING XMLTYPE (v_resp_msg)
                                     COLUMNS CRM_ID                  VARCHAR2 (12) PATH 'CRM_ID',
                                             GD_ID                   INTEGER PATH 'GD_ID',
                                             RESPONSE_MESSAGE        VARCHAR2 (256) PATH 'MESSAGE',
                                             RESPONSE_MESSAGE_CODE   INTEGER
                                                                        PATH 'MESSAGE_CODE') XT;

         IF (v_response_message_code IN (1,
                                         2,
                                         3,
                                         4))
         THEN
            IF (pINITIAL_DOC_STATUS = 'CRM_DECLINE')
            THEN
               UPDATE SYSDBA.FB_BSC_DOC
                  SET DOC_STATUS = 'STATUS_TO_GD_ERR',
                      DOC_STATUS_REASON =
                         'Ошибка обновления статуса в GreenData'
                WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

               COMMIT;

               UPDATE SYSDBA.FB_BSC_DOC
                  SET DOC_STATUS = 'DISAPPROVAL'
                WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

               COMMIT;
               pRESPONSE_MSG :=
                     'Не удалось передать окончательное решение. Обратитесь к администратору, или попробуйте позже. '
                  || v_response_message;
            ELSIF (pINITIAL_DOC_STATUS = 'CRM_CONFIRM')
            THEN
               UPDATE SYSDBA.FB_BSC_DOC
                  SET DOC_STATUS = 'STATUS_TO_GD_ERR',
                      DOC_STATUS_REASON = v_resp_msg
                WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

               COMMIT;

               UPDATE SYSDBA.FB_BSC_DOC
                  SET DOC_STATUS = 'DISAPPROVAL'
                WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

               COMMIT;
               NM_CRM.BSC_PKG.SEND_EMAIL (
                  'Не удалось подтвердить отказ в согласовании карточки',
                     '<p>Не удалось подтвердить отказ в согласовании карточки <a href="'
                  || pBSC_DOC_URL
                  || '">'
                  || (v_bsc_doc.BSCDOCTYPETEXT || ' ' || v_bsc_doc.DOCNUMBER)
                  || ' от '
                  || TO_CHAR (v_bsc_doc.DOCSTARTDATE, 'dd.MM.yyyy')
                  || '</a> в GreenData. Обратитесь к администратору.</p>',
                  v_user_email);
            END IF;
         ELSIF v_response_message_code = 0
         THEN
            IF (v_response_message = 'DISAPPROVAL')
            THEN
               UPDATE SYSDBA.FB_BSC_DOC
                  SET DOC_STATUS = 'DISAPPROVAL'
                WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

               COMMIT;
            ELSIF (v_response_message = 'APPROVAL')
            THEN
               UPDATE SYSDBA.FB_BSC_DOC
                  SET DOC_STATUS = 'APPROVAL'
                WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

               COMMIT;

               UPDATE SYSDBA.FB_BSC_DOC
                  SET DOC_STATUS = 'TO_EDK'
                WHERE FB_BSC_DOCID = pFB_BSC_DOCID;

               COMMIT;
            END IF;
         END IF;
      END IF;

      -- Если ответ все-таки получен то дропаем все джобы на повторные запросы
      IF (v_need_to_drop_jobs = 'T')
      THEN
         FOR jobCounter IN 1 .. 10
         LOOP
            DECLARE
               job_doesnt_exist   EXCEPTION;
               PRAGMA EXCEPTION_INIT (job_doesnt_exist, -27475);
            BEGIN
               DBMS_SCHEDULER.drop_job (
                  job_name   =>    'FB_BSC_REAPPROVE_DOC_STATUS_JOB_'
                                || pFB_BSC_DOCID
                                || '_'
                                || jobCounter);
            EXCEPTION
               WHEN job_doesnt_exist
               THEN
                  NULL;
            END;
         END LOOP;
      END IF;

      -- Если это уже 10 попытка отправки запроса и она также неудачная то отправляем Email
      IF (pTRY_TO_REAPPROVE_COUNT = 10 AND v_need_to_drop_jobs = 'F')
      THEN
         NM_CRM.BSC_PKG.SEND_EMAIL (
            'Не удалось подтвердить отказ в согласовании карточки',
               '<p>Не удалось подтвердить отказ в согласовании карточки <a href="'
            || pBSC_DOC_URL
            || '">'
            || (v_bsc_doc.BSCDOCTYPETEXT || ' ' || v_bsc_doc.DOCNUMBER)
            || ' от '
            || TO_CHAR (v_bsc_doc.DOCSTARTDATE, 'dd.MM.yyyy')
            || '</a> в GreenData. Обратитесь к администратору.</p>',
            v_user_email);
      END IF;

      COMMIT;
   EXCEPTION
      WHEN OTHERS
      THEN
         v_error_msg := SQLERRM;

         INSERT INTO NM_CRM.FB_BSC_LOG (CORRELATION_ID,
                                        CREATEDATE,
                                        XML_TEXT,
                                        QUEUE_NAME,
                                        SERVICE_NAME,
                                        ENTITYID,
                                        EXCEPTION_MSG)
              VALUES (pCORRELATIONID,
                      SYS_EXTRACT_UTC (SYSTIMESTAMP),
                      v_resp_msg,
                      v_crm_gd_queue_out,
                      'Exception',
                      pFB_BSC_DOCID,
                      v_error_msg);

         COMMIT;
   END;

   PROCEDURE SEND_RESPONSE_TO_GD (msg_code         IN INTEGER,
                                  msg_text         IN VARCHAR2,
                                  crm_id           IN VARCHAR2,
                                  gd_id            IN VARCHAR2,
                                  correlation_id   IN VARCHAR2,
                                  queue_name       IN VARCHAR2,
                                  exception_msg    IN VARCHAR2)
   IS
      v_fulloutmsg   VARCHAR2 (4000);
      v_outmsg_id    RAW (16);
   BEGIN
      v_fulloutmsg :=
         NM_CRM.BSC_PKG.FORM_GD_RESPONSE_MESSAGE (correlation_id,
                                                  crm_id,
                                                  gd_id,
                                                  msg_code,
                                                  msg_text);

      NM_CRM.BSC_PKG.ENQUEUE_MESSAGE (v_fulloutmsg,
                                      v_gd_send_response_service_name,
                                      correlation_id,
                                      queue_name,
                                      v_outmsg_id);

      INSERT INTO NM_CRM.FB_BSC_LOG (CORRELATION_ID,
                                     CREATEDATE,
                                     XML_TEXT,
                                     QUEUE_NAME,
                                     ENTITYID,
                                     SERVICE_NAME,
                                     EXCEPTION_MSG)
           VALUES (correlation_id,
                   SYS_EXTRACT_UTC (SYSTIMESTAMP),
                   v_fulloutmsg,
                   v_gd_crm_queue_out,
                   crm_id,
                   v_crm_send_reponse_service_name,
                   exception_msg);

      COMMIT;
   END;

   FUNCTION VALIDATE_GD_SEND_STATUS (OLD_STATUS   IN VARCHAR2,
                                     NEW_STATUS   IN VARCHAR2,
                                     DOC_TYPE     IN VARCHAR2)
      RETURN NUMBER
   IS
   BEGIN
      IF (    DOC_TYPE IN ('CONTRACT', 'CONTRACT_PROJ')
          AND (   (    OLD_STATUS = 'ON_FILLING'
                   AND NEW_STATUS IN ('REFUSED', 'ON_APPROVAL'))
               OR (    OLD_STATUS = 'ON_APPROVAL'
                   AND NEW_STATUS IN ('APPROVAL', 'DISAPPROVAL'))))
      THEN
         RETURN 1;
      END IF;

      IF (    DOC_TYPE = 'ARTICLE'
          AND (   (    OLD_STATUS = 'ON_FILLING'
                   AND NEW_STATUS IN ('REFUSED', 'ON_CHECK'))
               OR (    OLD_STATUS = 'ON_CHECK'
                   AND NEW_STATUS IN ('REFUSED', 'ON_APPROVAL'))
               OR (    OLD_STATUS = 'ON_APPROVAL'
                   AND NEW_STATUS IN ('APPROVAL', 'DISAPPROVAL'))))
      THEN
         RETURN 1;
      END IF;

      IF (    DOC_TYPE = 'ARTICLE_PROJ'
          AND (   (    OLD_STATUS = 'ON_FILLING'
                   AND NEW_STATUS IN ('REFUSED', 'ON_APPROVAL'))
               OR (    OLD_STATUS = 'ON_APPROVAL'
                   AND NEW_STATUS IN ('APPROVAL', 'DISAPPROVAL'))))
      THEN
         RETURN 1;
      END IF;

      IF (    DOC_TYPE = 'EXPENSE_SHEET'
          AND (   (    OLD_STATUS = 'ON_CHECK'
                   AND NEW_STATUS IN ('REFUSED', 'ON_APPROVAL'))
               OR (    OLD_STATUS = 'ON_APPROVAL'
                   AND NEW_STATUS IN ('APPROVAL', 'DISAPPROVAL'))))
      THEN
         RETURN 1;
      END IF;

      RETURN 0;
   END;

   PROCEDURE PROCESS_GD_SEND_STATUS_REQUEST (xmlobj           IN XMLTYPE,
                                             correlation_id   IN VARCHAR2)
   IS
   BEGIN
      FOR response
         IN (          SELECT RqUID,
                              XT.CRM_ID,
                              XT.GD_ID,
                              XT.DOC_TYPE_ID,
                              XT.DOC_TYPE_NAME,
                              XT.STATUS_ID,
                              XT.STATUS_NAME,
                              XT."COMMENT",
                              DOC.DOC_STATUS,
                              DOC.DOC_STATUS_TEXT,
                              (CASE
                                  WHEN XMLEXISTS (
                                          '/OpenAPI/Message/Object/DocumentStatus/STATUS_HISTORY/STATUS'
                                          PASSING xmlobj)
                                  THEN
                                     'T'
                                  ELSE
                                     'F'
                               END)
                                 STATUS_HISTORY
                         FROM XMLTABLE (
                                 'OpenAPI'
                                 PASSING xmlobj
                                 COLUMNS RqUID           VARCHAR2 (64) PATH 'RqUID/text()',
                                         CRM_ID          VARCHAR2 (12)
                                                            PATH 'Message/Object/DocumentStatus/CRM_ID',
                                         GD_ID           INTEGER
                                                            PATH 'Message/Object/DocumentStatus/GD_ID',
                                         DOC_TYPE_ID     VARCHAR2 (128)
                                                            PATH 'Message/Object/DocumentStatus/DOC_TYPE_ID',
                                         DOC_TYPE_NAME   VARCHAR2 (128)
                                                            PATH 'Message/Object/DocumentStatus/DOC_TYPE_NAME',
                                         STATUS_ID       VARCHAR2 (128)
                                                            PATH 'Message/Object/DocumentStatus/STATUS_ID',
                                         STATUS_NAME     VARCHAR2 (128)
                                                            PATH 'Message/Object/DocumentStatus/STATUS_NAME',
                                         "COMMENT"       VARCHAR2 (1024)
                                                            PATH 'Message/Object/DocumentStatus/COMMENT') XT
                              LEFT JOIN SYSDBA.FB_BSC_DOC DOC
                                 ON DOC.FB_BSC_DOCID = XT.CRM_ID)
      LOOP
         IF (VALIDATE_GD_SEND_STATUS (response.DOC_STATUS,
                                      response.STATUS_ID,
                                      response.DOC_TYPE_ID) = 0)
         THEN
            NM_CRM.BSC_PKG.SEND_RESPONSE_TO_GD (
               2,
                  'FROM_CRM_ERR. Карточка '
               || response.CRM_ID
               || '. Обновление статуса запрещено. Текущий статус – '
               || response.DOC_STATUS_TEXT
               || '.',
               response.CRM_ID,
               response.GD_ID,
               correlation_id,
               v_gd_crm_queue_out,
               '');
            RETURN;
         END IF;

         IF (response.DOC_STATUS IS NULL)
         THEN
            NM_CRM.BSC_PKG.SEND_RESPONSE_TO_GD (
               4,
                  'FROM_CRM_ERR. Карточка '
               || response.CRM_ID
               || ' не найдена.',
               response.CRM_ID,
               response.GD_ID,
               correlation_id,
               v_gd_crm_queue_out,
               '');
            RETURN;
         END IF;

         IF (   response.DOC_TYPE_ID NOT IN ('CONTRACT',
                                             'CONTRACT_PROJ',
                                             'ARTICLE',
                                             'ARTICLE_PROJ',
                                             'EXPENSE_SHEET')
             OR response.STATUS_ID NOT IN ('APPROVAL',
                                           'DISAPPROVAL',
                                           'REFUSED',
                                           'ON_FILLING',
                                           'ON_APPROVAL',
                                           'ON_CHECK'))
         THEN
            NM_CRM.BSC_PKG.SEND_RESPONSE_TO_GD (
               1,
               'FROM_CRM_ERR. Получен неопознанный тип запроса.',
               response.CRM_ID,
               response.GD_ID,
               correlation_id,
               v_gd_crm_queue_out,
               '');
            RETURN;
         END IF;

         -- Заполнение журнала согласования
         IF response.STATUS_HISTORY = 'T'
         THEN
            MERGE INTO SYSDBA.FB_BSC_APPR_LOG AL
                 USING (                   SELECT SL.BSC_DIVISIONCODE,
                                                  SL.BSC_DIVISIONNAME,
                                                  SL.BSC_RESPONSIBLEOFFICER,
                                                  SL.BSC_END_DATE,
                                                  SL.BSC_STATE,
                                                  SL.ISUNIFIED,
                                                  SL.BSC_NOTES
                                             FROM XMLTABLE (
                                                     '/OpenAPI/Message/Object/DocumentStatus/STATUS_HISTORY/STATUS'
                                                     PASSING xmlobj
                                                     COLUMNS BSC_DIVISIONCODE         VARCHAR2 (32)
                                                                                         PATH 'DIVISION_ID',
                                                             BSC_DIVISIONNAME         VARCHAR2 (256)
                                                                                         PATH 'DIVISION_NAME',
                                                             BSC_RESPONSIBLEOFFICER   VARCHAR2 (256)
                                                                                         PATH 'EMP_NAME',
                                                             BSC_END_DATE             VARCHAR2 (30)
                                                                                         PATH 'DATE',
                                                             BSC_STATE                VARCHAR2 (128)
                                                                                         PATH 'RESULT_ID',
                                                             ISUNIFIED                VARCHAR2 (12)
                                                                                         PATH 'IS_UNIFIED',
                                                             BSC_NOTES                VARCHAR2 (2048)
                                                                                         PATH 'NOTES') SL)
                       SL
                    ON (    AL.FB_BSC_DOCID = response.CRM_ID
                        AND AL.BSC_DIVISIONCODE = SL.BSC_DIVISIONCODE)
            WHEN MATCHED
            THEN
               UPDATE SET
                  AL.BSC_DIVISIONNAME = SL.BSC_DIVISIONNAME,
                  AL.BSC_RESPONSIBLEOFFICER = SL.BSC_RESPONSIBLEOFFICER,
                  AL.BSC_END_DATE = NM_CRM.Date4ISO (SL.BSC_END_DATE),
                  AL.BSC_STATE = SL.BSC_STATE,
                  AL.BSC_NOTES = SL.BSC_NOTES,
                  AL.ISUNIFIED = NM_CRM.BSC_PKG.STRING_TO_BOOL (SL.ISUNIFIED),
                  AL.BSC_MANAGERNOTES = response."COMMENT"
            WHEN NOT MATCHED
            THEN
               INSERT     (FB_BSC_APPR_LOGID,
                           CREATEUSER,
                           CREATEDATE,
                           MODIFYUSER,
                           MODIFYDATE,
                           BSC_DIVISIONCODE,
                           BSC_DIVISIONNAME,
                           BSC_RESPONSIBLEOFFICER,
                           BSC_END_DATE,
                           BSC_STATE,
                           BSC_NOTES,
                           BSC_MANAGERNOTES,
                           ISUNIFIED,
                           FB_BSC_DOCID)
                   VALUES (sysdba.FCREATESLXID ('FB_BSC_APPR_LOG'),
                           'ADMIN       ',
                           SYS_EXTRACT_UTC (SYSTIMESTAMP),
                           'ADMIN       ',
                           SYS_EXTRACT_UTC (SYSTIMESTAMP),
                           SL.BSC_DIVISIONCODE,
                           SL.BSC_DIVISIONNAME,
                           SL.BSC_RESPONSIBLEOFFICER,
                           NM_CRM.Date4ISO (SL.BSC_END_DATE),
                           SL.BSC_STATE,
                           SL.BSC_NOTES,
                           response."COMMENT",
                           NM_CRM.BSC_PKG.STRING_TO_BOOL (SL.ISUNIFIED),
                           response.CRM_ID);
         END IF;

         COMMIT;


         UPDATE SYSDBA.FB_BSC_DOC
            SET DOC_STATUS = response.STATUS_ID,
                DOC_STATUS_REASON =
                   CASE
                      WHEN response.STATUS_ID = 'DISAPPROVAL'
                      THEN
                         response."COMMENT"
                      ELSE
                         'Получен статус из GreenData'
                   END,
                DOCREADYFORRELATION =
                   CASE
                      WHEN response.STATUS_ID = 'APPROVAL' THEN 'T'
                      ELSE 'F'
                   END
          WHERE FB_BSC_DOCID = response.CRM_ID;

         NM_CRM.BSC_PKG.SEND_RESPONSE_TO_GD (0,
                                             response.STATUS_ID,
                                             response.CRM_ID,
                                             response.GD_ID,
                                             correlation_id,
                                             v_gd_crm_queue_out,
                                             '');
         COMMIT;
      END LOOP;
   END;

   FUNCTION VALIDATE_GD_SEND_DOCUMENT (DOC_STATUS   IN VARCHAR2,
                                       DOC_TYPE     IN VARCHAR2)
      RETURN NUMBER
   IS
   BEGIN
      IF (DOC_TYPE IN ('ARTICLE', 'ARTICLE_PROJ') AND DOC_STATUS = 'APPROVAL')
      THEN
         RETURN 1;
      END IF;

      IF (    DOC_TYPE IN ('CONTRACT', 'CONTRACT_PROJ')
          AND DOC_STATUS = 'ON_APPROVAL')
      THEN
         RETURN 1;
      END IF;

      RETURN 0;
   END;

   PROCEDURE PROCESS_GD_SEND_DOCUMENT_REQUEST (xmlobj           IN XMLTYPE,
                                               correlation_id   IN VARCHAR2)
   IS
      v_error_msg       VARCHAR2 (256);
      v_doc_subj_type   VARCHAR2 (256);
   BEGIN
      FOR response
         IN (                        SELECT XT.*,
                                            DOC.DOC_STATUS AS CURRENT_DOC_STATUS,
                                            DOC.DOC_STATUS_TEXT,
                                            (CASE
                                                WHEN XMLEXISTS (
                                                        '/OpenAPI/Message/Object/Document/STATEMENT_ITEM_LIST/STATEMENT_ITEM'
                                                        PASSING xmlobj)
                                                THEN
                                                   'T'
                                                ELSE
                                                   'F'
                                             END)
                                               IS_STATEMENT_ITEM_LIST
                                       FROM XMLTABLE (
                                               '/OpenAPI'
                                               PASSING xmlobj
                                               COLUMNS RqUID                         VARCHAR2 (64) PATH 'RqUID/text()',
                                                       FB_BSC_DOCID                  VARCHAR2 (12)
                                                                                        PATH 'Message/Object/Document/CRM_ID',
                                                       BSC_GREENDATA_DOC_ID          INTEGER
                                                                                        PATH 'Message/Object/Document/GD_ID',
                                                       BSC_DOC_TYPE                  VARCHAR2 (128)
                                                                                        PATH 'Message/Object/Document/DOC_TYPE_ID',
                                                       DOCSTARTDATE                  DATE
                                                                                        PATH 'Message/Object/Document/DOC_DATE',
                                                       FINPLANDATE                   DATE
                                                                                        PATH 'Message/Object/Document/DOC_PLAN_END_DATE',
                                                       DOCNUMBER                     VARCHAR2 (128)
                                                                                        PATH 'Message/Object/Document/DOC_NUM',
                                                       ISFRAMEWORK                   VARCHAR2 (8)
                                                                                        PATH 'Message/Object/Document/IS_FRAMEWORK',
                                                       DOCSUBJ                       VARCHAR2 (1200)
                                                                                        PATH 'Message/Object/Document/DOC_SUBJECT',
                                                       DOCSUBJTYPE_LIST              XMLTYPE
                                                                                        PATH 'Message/Object/Document/DOC_SUBJECT_TYPE_LIST',
                                                       DOC_BANK_RECEIVE              TIMESTAMP
                                                                                        PATH 'Message/Object/Document/DOC_BANK_RECEIVE_DATE',
                                                       PAY_WARRANTY                  VARCHAR2 (1200)
                                                                                        PATH 'Message/Object/Document/DELIV_PAYMENT_TERMS',
                                                       OBS_NEED                      VARCHAR2 (128)
                                                                                        PATH 'Message/Object/Document/ACC_OPEN_NEED_ID',
                                                       BSC_TYPE                      VARCHAR2 (128)
                                                                                        PATH 'Message/Object/Document/BSC_TYPE_ID',
                                                       OBSNECESSARITY                VARCHAR2 (128)
                                                                                        PATH 'Message/Object/Document/OPEN_NECESSARITY_ID',
                                                       VALUE_MIN                     NUMBER
                                                                                        PATH 'Message/Object/Document/AGREE_MIN_SUM',
                                                       ADVANCE_VALUE_MIN             NUMBER
                                                                                        PATH 'Message/Object/Document/AGREE_MIN_ADV_SUM',
                                                       ARTICLE_OUT_VALUE_MIN         NUMBER
                                                                                        PATH 'Message/Object/Document/AGREE_MIN_TOTAL_SUM',
                                                       VALUE_AND_NDS                 NUMBER
                                                                                        PATH 'Message/Object/Document/DOC_SUM',
                                                       VALUE_NDS                     NUMBER
                                                                                        PATH 'Message/Object/Document/VAT_SUM',
                                                       CURRENCY                      VARCHAR2 (6)
                                                                                        PATH 'Message/Object/Document/DOC_CURRENCY',
                                                       H_CONTRACTOR_PAYMENT_METHOD   VARCHAR2 (64)
                                                                                        PATH 'Message/Object/Document/SERVICE_CALC_MODE_ID',
                                                       H_CONTRACTOR_PAYMENT_PER      NUMBER
                                                                                        PATH 'Message/Object/Document/SERVICE_SUM_PERCENT',
                                                       H_CONTRACTOR_VALUE            NUMBER
                                                                                        PATH 'Message/Object/Document/SERVICE_SUM',
                                                       ADVANCE_PAYMENT               VARCHAR2 (8)
                                                                                        PATH 'Message/Object/Document/IS_ADV_PAY_AVAILABLE',
                                                       ADVANCE_PAYMENT_METHOD        VARCHAR2 (64)
                                                                                        PATH 'Message/Object/Document/ADV_CALC_MODE_ID',
                                                       ADVANCE_PAYMENT_PER           NUMBER
                                                                                        PATH 'Message/Object/Document/ADV_SUM_PERCENT',
                                                       ADVANCE_VALUE                 NUMBER
                                                                                        PATH 'Message/Object/Document/ADV_FIX_SUM',
                                                       ADVANCE_ORDER                 VARCHAR2 (64)
                                                                                        PATH 'Message/Object/Document/ADV_ORDER_SET_ID',
                                                       "RETENTION"                   VARCHAR2 (64)
                                                                                        PATH 'Message/Object/Document/WARANTY_KEEP_ID',
                                                       RETENTION_VALUE               NUMBER
                                                                                        PATH 'Message/Object/Document/WAR_KEEP_FIX_SUM',
                                                       RETENTION_PAYMENT_PER         NUMBER
                                                                                        PATH 'Message/Object/Document/WAR_KEEP_SUM_PERC',
                                                       RETENTION_OTHER               VARCHAR2 (64)
                                                                                        PATH 'Message/Object/Document/OTHER_KEEP_MODE_ID',
                                                       RETENTION_OTHER_VALUE         NUMBER
                                                                                        PATH 'Message/Object/Document/OTHER_KEEP_FIX_SUM',
                                                       RETENTION_OTHER_PER           NUMBER
                                                                                        PATH 'Message/Object/Document/OTHER_KEEP_SUM_PERC',
                                                       ADVANCE_DOC_NEED              VARCHAR2 (8)
                                                                                        PATH 'Message/Object/Document/IS_ADV_PAY_NEED_DOCS',
                                                       FILIAL_ID                     CHAR (12)
                                                                                        PATH 'Message/Object/Document/ORG_ID',
                                                       PARENT_DOC_ID                 CHAR (12)
                                                                                        PATH 'Message/Object/Document/PREV_DOC_ID',
                                                       DOCPROJECTID                  CHAR (12)
                                                                                        PATH 'Message/Object/Document/REL_PROJECT_ID',
                                                       DOC_STATUS                    VARCHAR2 (128)
                                                                                        PATH 'Message/Object/Document/STATUS_ID',
                                                       DOC_STATUS_LAST_CHANGE        DATE
                                                                                        PATH 'Message/Object/Document/STATUS_LAST_CHANGE',
                                                       DOC_SOURCE                    VARCHAR2 (128)
                                                                                        PATH 'Message/Object/Document/DOC_SOURCE_ID') XT
                                            LEFT JOIN SYSDBA.FB_BSC_DOC DOC
                                               ON DOC.FB_BSC_DOCID = XT.FB_BSC_DOCID)
      LOOP
         IF (NM_CRM.BSC_PKG.VALIDATE_GD_SEND_DOCUMENT (
                response.CURRENT_DOC_STATUS,
                response.BSC_DOC_TYPE) = 0)
         THEN
            NM_CRM.BSC_PKG.SEND_RESPONSE_TO_GD (
               2,
                  'FROM_CRM_ERR. Карточка '
               || response.FB_BSC_DOCID
               || '. Обновление статуса запрещено. Текущий статус – '
               || response.DOC_STATUS_TEXT
               || '.',
               response.FB_BSC_DOCID,
               response.BSC_GREENDATA_DOC_ID,
               correlation_id,
               v_gd_crm_queue_out,
               '');
            RETURN;
         END IF;

         IF (response.CURRENT_DOC_STATUS IS NULL)
         THEN
            NM_CRM.BSC_PKG.SEND_RESPONSE_TO_GD (
               4,
                  'FROM_CRM_ERR. Карточка '
               || response.FB_BSC_DOCID
               || ' не найдена.',
               response.FB_BSC_DOCID,
               response.BSC_GREENDATA_DOC_ID,
               correlation_id,
               v_gd_crm_queue_out,
               '');
            RETURN;
         END IF;

         BEGIN
                     SELECT LISTAGG (XT.SUBJ_TYPE_ID, ';')
                               WITHIN GROUP (ORDER BY XT.SUBJ_TYPE_ID)
                       INTO v_doc_subj_type
                       FROM XMLTABLE ('/DOC_SUBJECT_TYPE_LIST/DOC_SUBJECT_TYPE'
                                      PASSING response.DOCSUBJTYPE_LIST
                                      COLUMNS SUBJ_TYPE_ID   VARCHAR2 (64) PATH 'ID') XT;

            IF (response.IS_STATEMENT_ITEM_LIST = 'T')
            THEN
               FOR statementItem
                  IN (             SELECT SI.*
                                     FROM XMLTABLE (
                                             '/OpenAPI/Message/Object/Document/STATEMENT_ITEM_LIST/STATEMENT_ITEM'
                                             PASSING xmlobj
                                             COLUMNS BACKINGMAINID      CHAR (12)
                                                                           PATH 'BACKING_DOC_CRM_ID',
                                                     MAINID             CHAR (12)
                                                                           PATH 'STATEMENT_CRM_ID',
                                                     GDITEMPARENTID     CHAR (12)
                                                                           PATH 'STATEMENT_ITEM_PARENT_GD_ID',
                                                     GDITEMID           VARCHAR2 (12)
                                                                           PATH 'STATEMENT_ITEM_GD_ID',
                                                     ITEMCODE           VARCHAR2 (50)
                                                                           PATH 'STATEMENT_ITEM_CODE',
                                                     ITEMNAME           VARCHAR2 (512)
                                                                           PATH 'STATEMENT_ITEM_NAME',
                                                     ITEMACCOUNTCFTID   VARCHAR2 (20)
                                                                           PATH 'STATEMENT_ITEM_ACCOUNT_CFT_ID',
                                                     MAINACCOUNT        VARCHAR2 (20)
                                                                           PATH 'STATEMENT_ITEM_ACCOUNT_NUM',
                                                     ITEMLIM            NUMBER
                                                                           PATH 'STATEMENT_ITEM_LIMIT',
                                                     ITEMLIMTERM        DATE
                                                                           PATH 'STATEMENT_ITEM_INVALIDATION_DATE',
                                                     ISITEMADV          VARCHAR2 (12)
                                                                           PATH 'STATEMENT_ITEM_IS_ITEM_ADV',
                                                     ISWOARTICLE        VARCHAR2 (12)
                                                                           PATH 'STATEMENT_ITEM_IS_PAY_POSSIBLE',
                                                     ISPROFIT           VARCHAR2 (12)
                                                                           PATH 'STATEMENT_ITEM_IS_PROFIT',
                                                     ISOWNFUNDS         VARCHAR2 (12)
                                                                           PATH 'STATEMENT_ITEM_IS_OWN_FUNDS') SI)
               LOOP
                  INSERT INTO SYSDBA.FB_BSC_ES_ITEM (FB_BSC_ES_ITEMID,
                                                     CREATEDATE,
                                                     CREATEUSER,
                                                     MODIFYDATE,
                                                     MODIFYUSER,
                                                     BACKINGMAINID,
                                                     GDITEMPARENTID,
                                                     GDITEMID,
                                                     ISITEMADV,
                                                     ISOWNFUNDS,
                                                     ISPROFIT,
                                                     ISWOARTICLE,
                                                     ITEMCODE,
                                                     ITEMLIM,
                                                     ITEMLIMTERM,
                                                     ITEMNAME,
                                                     MAINID,
                                                     ITEMACCOUNTCFTID,
                                                     MAINACCOUNT)
                          VALUES (
                                    SYSDBA.FCREATESLXID ('FB_BSC_ES_ITEM'),
                                    SYS_EXTRACT_UTC (SYSTIMESTAMP),
                                    'ADMIN       ',
                                    SYS_EXTRACT_UTC (SYSTIMESTAMP),
                                    'ADMIN       ',
                                    statementItem.BACKINGMAINID,
                                    statementItem.GDITEMPARENTID,
                                    statementItem.GDITEMID,
                                    NM_CRM.BSC_PKG.STRING_TO_BOOL (
                                       statementItem.ISITEMADV),
                                    NM_CRM.BSC_PKG.STRING_TO_BOOL (
                                       statementItem.ISOWNFUNDS),
                                    NM_CRM.BSC_PKG.STRING_TO_BOOL (
                                       statementItem.ISPROFIT),
                                    NM_CRM.BSC_PKG.STRING_TO_BOOL (
                                       statementItem.ISWOARTICLE),
                                    statementItem.ITEMCODE,
                                    statementItem.ITEMLIM,
                                    statementItem.ITEMLIMTERM,
                                    statementItem.ITEMNAME,
                                    statementItem.MAINID,
                                    statementItem.ITEMACCOUNTCFTID,
                                    statementItem.MAINACCOUNT);
               END LOOP;
            END IF;

            COMMIT;

            UPDATE SYSDBA.FB_BSC_DOC
               SET BSC_GREENDATA_DOC_ID =
                      NVL (response.BSC_GREENDATA_DOC_ID,
                           BSC_GREENDATA_DOC_ID),
                   BSC_DOC_TYPE = NVL (response.BSC_DOC_TYPE, BSC_DOC_TYPE),
                   OBSNECESSARITY =
                      NVL (response.OBSNECESSARITY, OBSNECESSARITY),
                   DOCSTARTDATE = NVL (response.DOCSTARTDATE, DOCSTARTDATE),
                   FINPLANDATE = NVL (response.FINPLANDATE, FINPLANDATE),
                   DOCNUMBER = NVL (response.DOCNUMBER, DOCNUMBER),
                   ISFRAMEWORK =
                      NVL (
                         NM_CRM.BSC_PKG.STRING_TO_BOOL (response.ISFRAMEWORK),
                         ISFRAMEWORK),
                   DOCSUBJ = NVL (response.DOCSUBJ, DOCSUBJ),
                   DOCSUBJTYPE = NVL (v_doc_subj_type, DOCSUBJTYPE),
                   DOC_BANK_RECEIVE =
                      NVL (response.DOC_BANK_RECEIVE, DOC_BANK_RECEIVE),
                   PAY_WARRANTY = NVL (response.PAY_WARRANTY, PAY_WARRANTY),
                   OBS_NEED = NVL (response.OBS_NEED, OBS_NEED),
                   BSC_TYPE = NVL (response.BSC_TYPE, BSC_TYPE),
                   VALUE_MIN = NVL (response.VALUE_MIN, VALUE_MIN),
                   ADVANCE_VALUE_MIN =
                      NVL (response.ADVANCE_VALUE_MIN, ADVANCE_VALUE_MIN),
                   ARTICLE_OUT_VALUE_MIN =
                      NVL (response.ARTICLE_OUT_VALUE_MIN,
                           ARTICLE_OUT_VALUE_MIN),
                   VALUE_AND_NDS = NVL (response.VALUE_AND_NDS, VALUE_AND_NDS),
                   VALUE_NDS = NVL (response.VALUE_NDS, VALUE_NDS),
                   CURRENCY = NVL (response.CURRENCY, CURRENCY),
                   H_CONTRACTOR_PAYMENT_METHOD =
                      NVL (response.H_CONTRACTOR_PAYMENT_METHOD,
                           H_CONTRACTOR_PAYMENT_METHOD),
                   H_CONTRACTOR_PAYMENT_PER =
                      NVL (response.H_CONTRACTOR_PAYMENT_PER,
                           H_CONTRACTOR_PAYMENT_PER),
                   H_CONTRACTOR_VALUE =
                      NVL (response.H_CONTRACTOR_VALUE, H_CONTRACTOR_VALUE),
                   ADVANCE_PAYMENT =
                      NVL (
                         NM_CRM.BSC_PKG.STRING_TO_BOOL (
                            response.ADVANCE_PAYMENT),
                         ADVANCE_PAYMENT),
                   ADVANCE_PAYMENT_METHOD =
                      NVL (response.ADVANCE_PAYMENT_METHOD,
                           ADVANCE_PAYMENT_METHOD),
                   ADVANCE_PAYMENT_PER =
                      NVL (response.ADVANCE_PAYMENT_PER, ADVANCE_PAYMENT_PER),
                   ADVANCE_VALUE = NVL (response.ADVANCE_VALUE, ADVANCE_VALUE),
                   ADVANCE_ORDER = NVL (response.ADVANCE_ORDER, ADVANCE_ORDER),
                   "RETENTION" = NVL (response."RETENTION", "RETENTION"),
                   RETENTION_VALUE =
                      NVL (response.RETENTION_VALUE, RETENTION_VALUE),
                   RETENTION_PAYMENT_PER =
                      NVL (response.RETENTION_PAYMENT_PER,
                           RETENTION_PAYMENT_PER),
                   RETENTION_OTHER =
                      NVL (response.RETENTION_OTHER, RETENTION_OTHER),
                   RETENTION_OTHER_VALUE =
                      NVL (response.RETENTION_OTHER_VALUE,
                           RETENTION_OTHER_VALUE),
                   RETENTION_OTHER_PER =
                      NVL (response.RETENTION_OTHER_PER, RETENTION_OTHER_PER),
                   ADVANCE_DOC_NEED =
                      NVL (
                         NM_CRM.BSC_PKG.STRING_TO_BOOL (
                            response.ADVANCE_DOC_NEED),
                         ADVANCE_DOC_NEED),
                   FILIAL_ID = NVL (response.FILIAL_ID, FILIAL_ID),
                   PARENT_DOC_ID = NVL (response.PARENT_DOC_ID, PARENT_DOC_ID),
                   DOCPROJECTID = NVL (response.DOCPROJECTID, DOCPROJECTID),
                   DOC_STATUS_LAST_CHANGE =
                      NVL (response.DOC_STATUS_LAST_CHANGE,
                           DOC_STATUS_LAST_CHANGE),
                   DOC_SOURCE = NVL (response.DOC_SOURCE, DOC_SOURCE)
             WHERE FB_BSC_DOCID = response.FB_BSC_DOCID;

            COMMIT;

            -- Оповещение о смене статуса
            IF (    response.DOC_STATUS = 'APPROVAL'
                AND response.BSC_DOC_TYPE IN ('ARTICLE', 'ARTICLE_PROJ'))
            THEN
               NM_CRM.BSC_PKG.SEND_EMAIL_ABOUT_SEND_DOCUMENT (
                  response.FB_BSC_DOCID);
            END IF;
         EXCEPTION
            WHEN OTHERS
            THEN
               v_error_msg := SQLERRM;
               NM_CRM.BSC_PKG.SEND_RESPONSE_TO_GD (
                  3,
                     'FROM_CRM_ERR. Карточка '
                  || response.FB_BSC_DOCID
                  || '. Ошибка обновления.',
                  response.FB_BSC_DOCID,
                  response.BSC_GREENDATA_DOC_ID,
                  correlation_id,
                  v_gd_crm_queue_out,
                  v_error_msg);
               RETURN;
         END;

         NM_CRM.BSC_PKG.SEND_RESPONSE_TO_GD (0,
                                             response.DOC_STATUS,
                                             response.FB_BSC_DOCID,
                                             response.BSC_GREENDATA_DOC_ID,
                                             correlation_id,
                                             v_gd_crm_queue_out,
                                             '');
      END LOOP;
   END;

   FUNCTION VALIDATE_GD_SEND_STATEMENT (DOC_STATUS   IN VARCHAR2,
                                        DOC_TYPE     IN VARCHAR2)
      RETURN NUMBER
   IS
   BEGIN
      IF (DOC_TYPE = 'EXPENSE_SHEET' AND DOC_STATUS = 'APPROVAL')
      THEN
         RETURN 1;
      END IF;

      RETURN 0;
   END;

   PROCEDURE PROCESS_GD_SEND_STATEMENT_REQUEST (xmlobj           IN XMLTYPE,
                                                correlation_id   IN VARCHAR2)
   IS
      v_error_msg       VARCHAR2 (256);
      v_doc_subj_type   VARCHAR2 (256);
   BEGIN
      FOR response
         IN (                   SELECT XT.*,
                                       TO_DATE (XT.DOC_BANK_RECEIVE_STR,
                                                'yyyy-mm-dd"T"HH24:mi:ss')
                                          AS DOC_BANK_RECEIVE,
                                       DOC.DOC_STATUS AS CURRENT_DOC_STATUS,
                                       DOC.DOC_STATUS_TEXT,
                                       DOC.BSC_DOC_TYPE
                                  FROM XMLTABLE (
                                          '/OpenAPI'
                                          PASSING xmlobj
                                          COLUMNS RqUID                    VARCHAR2 (64) PATH 'RqUID/text()',
                                                  FB_BSC_DOCID             VARCHAR2 (12)
                                                                              PATH 'Message/Object/Statement/CRM_ID',
                                                  BSC_GREENDATA_DOC_ID     INTEGER
                                                                              PATH 'Message/Object/Statement/GD_ID',
                                                  OBS_ACCOUNT_NUM          VARCHAR2 (20)
                                                                              PATH 'Message/Object/Statement/BANK_ACC_ID',
                                                  OBSACCOUNTBIC            VARCHAR2 (32)
                                                                              PATH 'Message/Object/Statement/BANK_ACC_BIC',
                                                  OBSACCOUNTCFTID          VARCHAR2 (32)
                                                                              PATH 'Message/Object/Statement/BANK_ACC_CFT_ID',
                                                  OBSACCOWNERCRMID         CHAR (12)
                                                                              PATH 'Message/Object/Statement/BANK_ACC_OWNER_CRM_ID',
                                                  OBSACCOWNERCFTID         VARCHAR2 (32)
                                                                              PATH 'Message/Object/Statement/BANK_ACC_OWNER_CFT_ID',
                                                  DOCNUMBER                VARCHAR2 (128)
                                                                              PATH 'Message/Object/Statement/DOC_NUM',
                                                  DOCSTARTDATE             DATE
                                                                              PATH 'Message/Object/Statement/DOC_DATE',
                                                  DOC_BANK_RECEIVE_STR     VARCHAR2 (128)
                                                                              PATH 'Message/Object/Statement/RECEIVE_DATE',
                                                  VALUE_AND_NDS            NUMBER (17, 4)
                                                                              PATH 'Message/Object/Statement/STATEMENT_AMOUNT',
                                                  DOC_SOURCE               VARCHAR2 (128)
                                                                              PATH 'Message/Object/Statement/DOC_SOURCE_ID',
                                                  DOC_VERSION              INTEGER
                                                                              PATH 'Message/Object/Statement/DOC_VERSION',
                                                  EXPENSE_SHEET_ID         CHAR (12)
                                                                              PATH 'Message/Object/Statement/INTERNAL_ID',
                                                  EXPENSE_SHEET_PARENT     CHAR (12)
                                                                              PATH 'Message/Object/Statement/INTERNAL_PARENT_ID',
                                                  EXPENSESHEETCONTRACTID   CHAR (12)
                                                                              PATH 'Message/Object/Statement/CONTRACT_ID',
                                                  FILIAL_ID                CHAR (12)
                                                                              PATH 'Message/Object/Statement/ORG_ID') XT
                                       LEFT JOIN SYSDBA.FB_BSC_DOC DOC
                                          ON DOC.FB_BSC_DOCID = XT.FB_BSC_DOCID)
      LOOP
         IF (VALIDATE_GD_SEND_STATEMENT (response.CURRENT_DOC_STATUS,
                                         response.BSC_DOC_TYPE) = 0)
         THEN
            NM_CRM.BSC_PKG.SEND_RESPONSE_TO_GD (
               2,
                  'FROM_CRM_ERR. Карточка '
               || response.FB_BSC_DOCID
               || '. Обновление статуса запрещено. Текущий статус – '
               || response.DOC_STATUS_TEXT
               || '.',
               response.FB_BSC_DOCID,
               response.BSC_GREENDATA_DOC_ID,
               correlation_id,
               v_gd_crm_queue_out,
               '');
            RETURN;
         END IF;

         IF (response.CURRENT_DOC_STATUS IS NULL)
         THEN
            NM_CRM.BSC_PKG.SEND_RESPONSE_TO_GD (
               3,
                  'FROM_CRM_ERR. Карточка '
               || response.FB_BSC_DOCID
               || ' не найдена.',
               response.FB_BSC_DOCID,
               response.BSC_GREENDATA_DOC_ID,
               correlation_id,
               v_gd_crm_queue_out,
               '');
            RETURN;
         END IF;

         BEGIN
            UPDATE SYSDBA.FB_BSC_DOC
               SET BSC_GREENDATA_DOC_ID =
                      NVL (response.BSC_GREENDATA_DOC_ID,
                           BSC_GREENDATA_DOC_ID),
                   OBS_ACCOUNT_NUM =
                      NVL (response.OBS_ACCOUNT_NUM, OBS_ACCOUNT_NUM),
                   OBSACCOUNTBIC = NVL (response.OBSACCOUNTBIC, OBSACCOUNTBIC),
                   OBSACCOUNTCFTID =
                      NVL (response.OBSACCOUNTCFTID, OBSACCOUNTCFTID),
                   OBSACCOWNERCRMID =
                      NVL (response.OBSACCOWNERCRMID, OBSACCOWNERCRMID),
                   OBSACCOWNERCFTID =
                      NVL (response.OBSACCOWNERCFTID, OBSACCOWNERCFTID),
                   DOCNUMBER = NVL (response.DOCNUMBER, DOCNUMBER),
                   DOCSTARTDATE = NVL (response.DOCSTARTDATE, DOCSTARTDATE),
                   DOC_BANK_RECEIVE =
                      NVL (response.DOC_BANK_RECEIVE, DOC_BANK_RECEIVE),
                   VALUE_AND_NDS = NVL (response.VALUE_AND_NDS, VALUE_AND_NDS),
                   DOC_SOURCE = NVL (response.DOC_SOURCE, DOC_SOURCE),
                   DOC_VERSION = NVL (response.DOC_VERSION, DOC_VERSION),
                   EXPENSE_SHEET_ID =
                      NVL (response.EXPENSE_SHEET_ID, EXPENSE_SHEET_ID),
                   EXPENSE_SHEET_PARENT =
                      NVL (response.EXPENSE_SHEET_PARENT,
                           EXPENSE_SHEET_PARENT),
                   EXPENSESHEETCONTRACTID =
                      NVL (response.EXPENSESHEETCONTRACTID,
                           EXPENSESHEETCONTRACTID)
             WHERE FB_BSC_DOCID = response.FB_BSC_DOCID;

            COMMIT;
         EXCEPTION
            WHEN OTHERS
            THEN
               v_error_msg := SQLERRM;
               NM_CRM.BSC_PKG.SEND_RESPONSE_TO_GD (
                  3,
                     'FROM_CRM_ERR. Карточка '
                  || response.FB_BSC_DOCID
                  || '. Ошибка обновления.',
                  response.FB_BSC_DOCID,
                  response.BSC_GREENDATA_DOC_ID,
                  correlation_id,
                  v_gd_crm_queue_out,
                  v_error_msg);
               RETURN;
         END;

         NM_CRM.BSC_PKG.SEND_RESPONSE_TO_GD (0,
                                             response.CURRENT_DOC_STATUS,
                                             response.FB_BSC_DOCID,
                                             response.BSC_GREENDATA_DOC_ID,
                                             correlation_id,
                                             v_gd_crm_queue_out,
                                             '');
      END LOOP;
   END;

   FUNCTION TAKE_VALUE_BY_PAYMENT_METHOD (PAYMENT_METHOD   IN VARCHAR2,
                                          PER_VALUE        IN NUMBER,
                                          SUM_VALUE        IN NUMBER)
      RETURN NUMBER
   IS
   BEGIN
      RETURN CASE
                WHEN PAYMENT_METHOD = 'FIX_AMOUNT' THEN SUM_VALUE
                WHEN PAYMENT_METHOD = 'PER_AMOUNT' THEN PER_VALUE
                ELSE NULL
             END;
   END;

   FUNCTION MAP_PAYMENT_METHOD_TO_CFT (PAYMENT_METHOD IN VARCHAR2)
      RETURN NUMBER
   IS
   BEGIN
      RETURN CASE
                WHEN PAYMENT_METHOD = 'FIX_AMOUNT' THEN 0
                WHEN PAYMENT_METHOD = 'PER_AMOUNT' THEN 1
                ELSE NULL
             END;
   END;

   FUNCTION MAP_DOC_TO_XML_CFT (pFB_BSC_DOCID    IN CHAR,
                                pCORRELATIONID   IN VARCHAR2)
      RETURN CLOB
   IS
      response_msg   CLOB;
   BEGIN
      SELECT XMLELEMENT (
                "CFTServiceRequest",
                XMLELEMENT ("SystemId", 'CFT'),
                XMLELEMENT ("MessageId", pCORRELATIONID),
                XMLELEMENT ("RequestType", v_cft_send_doc_service_name),
                XMLELEMENT (
                   "Request",
                   XMLELEMENT ("IsFrameDoc", 0),
                   XMLELEMENT ("IsSpecification", 0),
                   XMLELEMENT ("FrameDog"),
                   XMLELEMENT ("HeadLevel"),
                   XMLELEMENT ("ReqExec",
                               XMLELEMENT ("Id", DOCEXEC.EXTERNALACCOUNTNO),
                               XMLELEMENT ("ExtId", DOCEXEC.ACCOUNTID),
                               XMLELEMENT ("Inn", DOCEXEC.INN),
                               XMLELEMENT ("Kpp", DOCEXEC.KPP),
                               XMLELEMENT ("Name", DOCEXEC.ACCOUNT)),
                   XMLELEMENT (
                      "Filial",
                      (SELECT DATAVALUE
                         FROM SYSDBA.CUSTOMSETTINGS
                        WHERE     DESCRIPTION = 'BSC_Default_Branch_Send_CFT'
                              AND ROWNUM = 1)),
                   XMLELEMENT ("UserAccept"),
                   XMLELEMENT ("Num", doc.DOCNUMBER),
                   XMLELEMENT ("VidEscort", doc.BSC_TYPE),
                   XMLELEMENT ("DateBegin", doc.DOCSTARTDATE),
                   XMLELEMENT ("DateEnd", doc.FINPLANDATE),
                   (SELECT XMLELEMENT (
                              "TypeDogArr",
                              XMLAGG (XMLELEMENT ("TypeDog", dst.SUBJ_TYPE)))
                      FROM ( (    SELECT TRIM (
                                            REGEXP_SUBSTR (
                                               (SELECT DOCSUBJTYPE -- Костыль (Oracle не видит doc.DOCSUBTYPE из-за тройной вложенности...)
                                                  FROM SYSDBA.FB_BSC_DOC
                                                 WHERE FB_BSC_DOCID =
                                                          pFB_BSC_DOCID),
                                               '[^;]+',
                                               1,
                                               LEVEL))
                                            SUBJ_TYPE
                                    FROM DUAL
                              CONNECT BY LEVEL <=
                                              REGEXP_COUNT (
                                                 (SELECT DOCSUBJTYPE -- Костыль (Oracle не видит doc.DOCSUBTYPE из-за тройной вложенности...)
                                                    FROM SYSDBA.FB_BSC_DOC
                                                   WHERE FB_BSC_DOCID =
                                                            pFB_BSC_DOCID),
                                                 ';')
                                            + 1) dst)),
                   XMLELEMENT ("DogText", doc.DOCSUBJ),
                   XMLELEMENT ("DeliveryCond", doc.PAY_WARRANTY),
                   XMLELEMENT ("ReqClient",
                               XMLELEMENT ("Id", DOCORDER.EXTERNALACCOUNTNO),
                               XMLELEMENT ("ExtId", DOCORDER.ACCOUNTID),
                               XMLELEMENT ("Inn", DOCORDER.INN),
                               XMLELEMENT ("Kpp", DOCORDER.KPP),
                               XMLELEMENT ("Name", DOCORDER.ACCOUNT)),
                   XMLELEMENT ("Summa",
                               XMLELEMENT ("TypeSum", 0),
                               XMLELEMENT ("Value", doc.VALUE_AND_NDS)),
                   XMLELEMENT (
                      "SumGen",
                      XMLELEMENT (
                         "TypeSum",
                         MAP_PAYMENT_METHOD_TO_CFT (
                            doc.H_CONTRACTOR_PAYMENT_METHOD)),
                      XMLELEMENT (
                         "Value",
                         TAKE_VALUE_BY_PAYMENT_METHOD (
                            doc.H_CONTRACTOR_PAYMENT_METHOD,
                            doc.H_CONTRACTOR_PAYMENT_PER,
                            doc.H_CONTRACTOR_VALUE))),
                   XMLELEMENT (
                      "SumGrn",
                      XMLELEMENT ("TypeSum",
                                  MAP_PAYMENT_METHOD_TO_CFT (doc.RETENTION)),
                      XMLELEMENT (
                         "Value",
                         TAKE_VALUE_BY_PAYMENT_METHOD (
                            doc.RETENTION,
                            doc.RETENTION_PAYMENT_PER,
                            doc.RETENTION_VALUE))),
                   XMLELEMENT (
                      "SumAvn",
                      XMLELEMENT (
                         "TypeSum",
                         MAP_PAYMENT_METHOD_TO_CFT (
                            doc.ADVANCE_PAYMENT_METHOD)),
                      XMLELEMENT (
                         "Value",
                         TAKE_VALUE_BY_PAYMENT_METHOD (
                            doc.ADVANCE_PAYMENT_METHOD,
                            doc.ADVANCE_PAYMENT_PER,
                            doc.ADVANCE_VALUE))),
                   XMLELEMENT (
                      "AvnText",
                      TRANSLATE_VALUE_BY_DICTIONARY (
                         doc.ADVANCE_ORDER,
                         'Порядок зачета аванса БСК')),
                   XMLELEMENT ("SumGuarantee"),
                   XMLELEMENT (
                      "SumOthers",
                      XMLELEMENT (
                         "TypeSum",
                         MAP_PAYMENT_METHOD_TO_CFT (doc.RETENTION_OTHER)),
                      XMLELEMENT (
                         "Value",
                         TAKE_VALUE_BY_PAYMENT_METHOD (
                            doc.RETENTION_OTHER,
                            doc.RETENTION_OTHER_PER,
                            doc.RETENTION_OTHER_VALUE))),
                   XMLELEMENT (
                      "IsSupportDoc",
                      CASE
                         WHEN doc.ADVANCE_DOC_NEED = 'T'
                         THEN
                            1
                         WHEN (   doc.ISFRAMEWORK IS NULL
                               OR doc.ISFRAMEWORK = 'F')
                         THEN
                            0
                      END),
                   XMLELEMENT ("Note"),
                   (SELECT XMLELEMENT (
                              "DPVRArr",
                              XMLAGG (
                                 XMLELEMENT (
                                    "Dpvr",
                                    XMLELEMENT ("TypeDPVR",
                                                dpvrType.TypeDPVR),
                                    XMLELEMENT (
                                       "NameDPVR",
                                       TRANSLATE_VALUE_BY_DICTIONARY (
                                          dpvrType.TypeDPVR,
                                          'Вид документов в составе Пакета документов БСК')))))
                      FROM (    SELECT TRIM (
                                          REGEXP_SUBSTR (
                                             (SELECT CONTRACT_DPVR_DOC_TYPE -- Костыль (Oracle не видит doc.DOCSUBTYPE из-за тройной вложенности...)
                                                FROM SYSDBA.FB_BSC_DOC
                                               WHERE FB_BSC_DOCID = pFB_BSC_DOCID),
                                             '[^;]+',
                                             1,
                                             LEVEL))
                                          TypeDPVR
                                  FROM DUAL
                            CONNECT BY LEVEL <=
                                            REGEXP_COUNT (
                                               (SELECT CONTRACT_DPVR_DOC_TYPE -- Костыль (Oracle не видит doc.DOCSUBTYPE из-за тройной вложенности...)
                                                  FROM SYSDBA.FB_BSC_DOC
                                                 WHERE FB_BSC_DOCID =
                                                          pFB_BSC_DOCID),
                                               ';')
                                          + 1) dpvrType),
                   (SELECT XMLELEMENT (
                              "DocArr",
                              XMLAGG (XMLELEMENT ("Doc", bda.BSC_URL)))
                      FROM SYSDBA.FB_BSC_DOC_ATTACH bda
                     WHERE bda.FB_BSC_DOCID = pFB_BSC_DOCID))).GETCLOBVAL ()
        INTO response_msg
        FROM SYSDBA.FB_BSC_DOC doc
             LEFT JOIN SYSDBA.ACCOUNT DOCEXEC
                ON (DOCEXEC.ACCOUNTID = doc.EXECUTORID)
             LEFT JOIN SYSDBA.ACCOUNT DOCORDER
                ON (DOCORDER.ACCOUNTID = doc.ORDERID)
       WHERE doc.FB_BSC_DOCID = pFB_BSC_DOCID;

      RETURN response_msg;
   END;

   PROCEDURE SEND_DOC_TO_CFT_P (pFB_BSC_DOCID IN CHAR)
   IS
      v_outmsg_id                RAW (16);
      v_fulloutmsg               CLOB;
      v_correlation_id           VARCHAR2 (32) := '123';        --SYS_GUID ();
      v_error_msg                VARCHAR2 (512);
      v_expiration_time          NUMBER(12);
   BEGIN
      -- Получаем время ожидания из пользовательских настроек
      BEGIN
         SELECT TO_NUMBER (DATAVALUE,
                           'FM99999999999999999D9999',
                           'nls_numeric_characters = ''. ''')
           INTO v_expiration_time
           FROM SYSDBA.CUSTOMSETTINGS
          WHERE     CATEGORY = 'Bank Support Contract'
                AND DESCRIPTION = 'BSC_Doc_Send_CFT_Timeout';
      EXCEPTION
         WHEN OTHERS
         THEN
            v_expiration_time := NULL;
      END;

      -- Формируем XML
      SELECT NM_CRM.BSC_PKG.MAP_DOC_TO_XML_CFT (pFB_BSC_DOCID, v_correlation_id)
        INTO v_fulloutmsg
        FROM DUAL;

      -- Отправляем XML
      NM_CRM.BSC_PKG.ENQUEUE_MESSAGE (v_fulloutmsg,
                                      v_cft_send_doc_service_name,
                                      v_correlation_id,
                                      v_crm_cft_queue_out,
                                      v_outmsg_id);

      -- Пишем в лог XML которую отправляем
      INSERT INTO NM_CRM.FB_BSC_LOG (CORRELATION_ID,
                                     CREATEDATE,
                                     XML_TEXT,
                                     QUEUE_NAME,
                                     SERVICE_NAME,
                                     ENTITYID)
           VALUES (v_correlation_id,
                   SYS_EXTRACT_UTC (SYSTIMESTAMP),
                   v_fulloutmsg,
                   v_crm_cft_queue_out,
                   v_cft_send_doc_service_name,
                   pFB_BSC_DOCID);

      COMMIT;

   EXCEPTION
      WHEN OTHERS
      THEN
         v_error_msg := SQLERRM;

         INSERT INTO NM_CRM.FB_BSC_LOG (CORRELATION_ID,
                                        CREATEDATE,
                                        XML_TEXT,
                                        QUEUE_NAME,
                                        SERVICE_NAME,
                                        ENTITYID,
                                        EXCEPTION_MSG)
              VALUES (v_correlation_id,
                      SYS_EXTRACT_UTC (SYSTIMESTAMP),
                      v_fulloutmsg,
                      v_crm_cft_queue_out,
                      'Exception',
                      pFB_BSC_DOCID,
                      v_error_msg);

         COMMIT;
   END;

   PROCEDURE SEND_DOC_TO_CFT (pFB_BSC_DOCID IN CHAR)
   IS
   BEGIN
      DBMS_SCHEDULER.create_job (
         job_name     =>    'NM_CRM.SEND_DOC_TO_CFT_JOB_'
                         || pFB_BSC_DOCID,
         job_type     => 'PLSQL_BLOCK',
         job_action   =>    'begin NM_CRM.BSC_PKG.SEND_DOC_TO_CFT_P('''
                         || pFB_BSC_DOCID
                         || '''); end;',
         start_date   => SYSDATE,
         enabled      => TRUE,
         auto_drop    => TRUE,
         comments     => 'one-time job');
   EXCEPTION
      WHEN OTHERS
      THEN
         NULL;
   END;
END BSC_PKG;
/