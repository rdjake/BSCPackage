v_gd_send_additional_service_name   VARCHAR2 (64) := 'GreenData.Send.Additional';
 
 
 FUNCTION MAP_ADDITIONAL_TO_XML (pFB_BSC_DOCID IN CHAR)
      RETURN CLOB
   IS
      response_msg   CLOB;
   BEGIN
      SELECT XMLELEMENT (
                "OpenAPI",
                XMLELEMENT ("MessageType", v_gd_send_additional_service_name),
                XMLELEMENT (
                   "Message",
                   XMLELEMENT (
                      "Object",
                      XMLELEMENT (
                         "Additional",                      
                           XMLELEMENT ("CRM_ID", doc.FB_BSC_DOCID),
                           XMLELEMENT ("GD_ID", doc.BSC_GREENDATA_DOC_ID),
                           XMLELEMENT ("CFT_ID"),
                           XMLELEMENT ("CONTRACT_TREATY_ID",doc.MAINDOCID),
                           XMLELEMENT ("ADD_DOC_NUM",doc.DOCNUMBER),
                           XMLELEMENT ("ADD_AGREEMENT_DATE",doc.DOCSTARTDATE),
                           XMLELEMENT ("IS_MAIN_ATR_NO_CHANGE",doc.NOT_ATTRCHANGE),

                           XMLELEMENT ("IS_DOC_SUM_CHANGE"),
                           XMLELEMENT ("DOC_SUM_CHANGE_ID"),
                           XMLELEMENT ("DOC_SUM_CHANGE_NAME"),
                           XMLELEMENT ("DOC_SUM_CHANGE_VAL"),

                           XMLELEMENT ("IS_OTHER_KEEP_CHANGE"),
                           XMLELEMENT ("OTHER_KEEP_CHANGE_ID"),
                           XMLELEMENT ("OTHER_KEEP_CHANGE_NAME"),
                           XMLELEMENT ("OTHER_KEEP_CHANGE_MODE_ID"),
                           XMLELEMENT ("OTHER_KEEP_CHANGE_MODE_NAME"),
                           XMLELEMENT ("OTHER_KEEP_CHANGE_SUM"),
                           XMLELEMENT ("OTHER_KEEP_CHANGE_PERC"),

                           XMLELEMENT ("IS_WAR_KEEP_CHANGE"),
                           XMLELEMENT ("WAR_KEEP_CHANGE_ID"),
                           XMLELEMENT ("WAR_KEEP_CHANGE_NAME"),
                           XMLELEMENT ("WAR_KEEP_CHANGE_MODE_ID"),
                           XMLELEMENT ("WAR_KEEP_CHANGE_MODE_NAME"),

                           XMLELEMENT ("IS_ADVANCE_CHANGE"),
                           XMLELEMENT ("ADVANCE_CHANGE_ID"),
                           XMLELEMENT ("ADVANCE_CHANGE_NAME"),

                           XMLELEMENT ("IS_SERVICE_CHANGE"),
                           XMLELEMENT ("SERVICE_CHANGE_ID"),
                           XMLELEMENT ("SERVICE_CHANGE_NAME"),

                           XMLELEMENT ("ADD_AGR_COMMENT", doc.DOC_COMMENT),
                           XMLELEMENT ("ORG_ID", doc.FILIAL_ID),
                           XMLELEMENT ("CREATED_EMP",doc.BSC_DOC_USER_ID),
                           XMLELEMENT ("DOC_BANK_RECEIVE_DATE", doc.DOC_BANK_RECEIVE),
                           XMLELEMENT ("STATUS_ID",doc.DOC_STATUS),
                           XMLELEMENT ("STATUS_NAME", doc.DOC_STATUS_TEXT),
                           XMLELEMENT ("DOC_SOURCE_ID",doc.DOC_SOURCE),
                           XMLELEMENT ("DOC_SOURCE_NAME",(SELECT TEXT
                                                         FROM SYSDBA.PICKLIST
                                                         WHERE     PICKLISTID IN (SELECT ITEMID
                                                                                    FROM SYSDBA.PICKLIST
                                                                                 WHERE TEXT =
                                                                                          'Источник поступления карточки БСК')
                                                               AND SHORTTEXT = doc.DOC_SOURCE)),
                           (SELECT XMLELEMENT ("ATTACHED_FILE_LIST",
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
                                             "DOC_SUBJECT_TYPE_LIST",
                                             XMLAGG (
                                                XMLELEMENT (
                                                   "DOC_SUBJECT_TYPE",
                                                   XMLELEMENT ("ID", t1.SUBJ_TYPE),
                                                   XMLELEMENT ("NAME", t2.TEXT))))
                                       FROM ( (    SELECT TRIM (
                                                            REGEXP_SUBSTR (
                                                               doc.CONTRACT_SUBJ_TYPE,
                                                               '[^;]+',
                                                               1,
                                                               LEVEL))
                                                            SUBJ_TYPE
                                                   FROM DUAL
                                             CONNECT BY LEVEL <=
                                                               REGEXP_COUNT (
                                                                  doc.CONTRACT_SUBJ_TYPE,
                                                                  ';')
                                                            + 1) t1
                                             JOIN SYSDBA.PICKLIST t2
                                                ON     PICKLISTID IN (SELECT ITEMID
                                                                        FROM SYSDBA.PICKLIST
                                                                     WHERE TEXT =
                                                                              'Тип предмета Договора БСК')
                                                   AND SHORTTEXT = t1.SUBJ_TYPE)),
                           XMLELEMENT ("ADD_SUBJECT", doc.DOCSUBJ),
                           XMLELEMENT ("ADD_DELIV_PAYMENT_TERMS", doc.PAY_WARRANTY),
                           XMLELEMENT ("SERVICE_CHANGE_MODE_ID", doc.H_CONTRACTOR_PAYMENT_METHOD),
                           XMLELEMENT ("SERVICE_CHANGE_MODE_NAME",
                                                               (SELECT TEXT
                                                                  FROM SYSDBA.PICKLIST
                                                               WHERE     PICKLISTID IN (SELECT ITEMID
                                                                                          FROM SYSDBA.PICKLIST
                                                                                          WHERE TEXT =
                                                                                                   'Способ расчета БСК')
                                                                     AND SHORTTEXT =
                                                                              doc.H_CONTRACTOR_PAYMENT_METHOD)),
                           XMLELEMENT ("SERVICE_CHANGE_PERC", doc.H_CONTRACTOR_PAYMENT_PER),
                           XMLELEMENT ("SERVICE_CHANGE_SUM", doc.H_CONTRACTOR_VALUE),
                           XMLELEMENT ("ADVANCE_CHANGE_MODE_ID", doc.ADVANCE_PAYMENT_METHOD),
                           XMLELEMENT ("ADVANCE_CHANGE_MODE_NAME",
                                                      (SELECT TEXT
                                                         FROM SYSDBA.PICKLIST
                                                         WHERE     PICKLISTID IN (SELECT ITEMID
                                                                                    FROM SYSDBA.PICKLIST
                                                                                 WHERE TEXT =
                                                                                          'Способ расчета БСК')
                                                               AND SHORTTEXT =
                                                                     doc.ADVANCE_PAYMENT_METHOD)),
                           XMLELEMENT ("ADVANCE_CHANGE_PERC", doc.ADVANCE_PAYMENT_PER),
                           XMLELEMENT ("ADVANCE_CHANGE_SUM",doc.ADVANCE_VALUE),
                           XMLELEMENT ("WAR_KEEP_CHANGE_SUM",doc.RETENTION_VALUE),
                           XMLELEMENT ("WAR_KEEP_CHANGE_PERC",doc.RETENTION_PAYMENT_PER),
                           XMLELEMENT ("DOC_PLAN_END_DATE",doc.FINPLANDATE),
                           XMLELEMENT ("CUSTOMER_ID",doc.ORDERID),
                           XMLELEMENT ("CONTRACTOR_ID",doc.EXECUTORID),
                           XMLELEMENT ("CONTRACT_ID", doc.ADDPACKCONTRACTID),
                           XMLELEMENT ("STATEMENT_ITEM_LIST"))))).GETCLOBVAL ()
        INTO response_msg
        FROM SYSDBA.FB_BSC_DOC doc
        WHERE doc.FB_BSC_DOCID = pFB_BSC_DOCID;
      RETURN response_msg;
   END;



