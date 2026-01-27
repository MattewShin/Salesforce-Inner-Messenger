/**
 * ===========================================================================================
 * @description       : Helper class for retrieving Omni-Channel Presence Status IDs
 * @author            : CNXK
 * @last modified on  : 2025-01-XX
 * @last modified by  : CNXK
 * ===========================================================================================
 * Modification Log
 * Ver   Date         Author              Description
 * 1.0   2025-01-XX   CNXK                Initial version - Retrieving OK(Online) Presence Status ID for Omni-Channel integration
 * 2.0   2025-01-XX   CNXK                Updated to return both OnBreak and Available status IDs for break request integration
 * 
 * ===========================================================================================
 * ⚠️ IMPORTANT - Org-Specific Configuration Required
 * ===========================================================================================
 * This class queries Salesforce's built-in ServicePresenceStatus object.
 * The Presence Status values (names) can differ per organization.
 * 
 * DEFAULT VALUES (can vary):
 *   - OnBreak Status Name: "OnBreak" (조직에서 정의한 이름)
 *   - Available Status Name: "OK" or "Available" (조직에서 정의한 이름)
 * 
 * WHEN DEPLOYING TO NEW ORG:
 *   1. Check Setup > Omnichannel > Presence
 *   2. Note the DeveloperName and MasterLabel for each Presence Status
 *   3. If different from "OK", "OnBreak", "Available", update the SOQL queries below
 * 
 * EXAMPLE - If your Org uses different status names:
 *   Org A (current):
 *     - OnBreak (API: OnBreak)
 *     - OK (API: OK)
 *   
 *   Org B (new):
 *     - Break (API: Break)
 *     - Available (API: Available)
 *   
 *   Solution: Update line 34, 68 to match Org B's API names:
 *     WHERE DeveloperName = 'Break'
 *     WHERE DeveloperName = 'Available'
 */
public without sharing class OmniPresenceHelper {

    public class StatusIds {
        @AuraEnabled public String onBreakId;
        @AuraEnabled public String availableChatId;
    }

    /**
     * @description Retrieve Omni-Channel Presence Status IDs
     * 
     * This method queries ServicePresenceStatus object to find:
     *   1. OnBreak Status ID - used for break requests
     *   2. Available Status ID - used for normal chat availability
     * 
     * @return StatusIds wrapper containing both status IDs
     *         - onBreakId: ID of "OnBreak" presence status (null if not found)
     *         - availableChatId: ID of "OK" or "Available" presence status (null if not found)
     * 
     * @note Safe error handling: If one status is not found, continues to find the other
     *       Returns partial results if some statuses are found
     * 
     * ⚠️ Org-Specific: Status names can be customized in each organization
     *    See class-level documentation for configuration details
     */
    @AuraEnabled(cacheable=true)
    public static StatusIds getServicePresenceStatusId() {
        StatusIds result = new StatusIds();

        try {
            /**
             * Query 1: OnBreak Status
             * 
             * CUSTOMIZABLE: Update DeveloperName/MasterLabel if your Org uses different name
             * Example for Org with "Break" instead of "OnBreak":
             *   WHERE DeveloperName = 'Break' OR MasterLabel = 'Break'
             */
            List<ServicePresenceStatus> onBreakStatuses = [
                SELECT Id, DeveloperName, MasterLabel
                FROM ServicePresenceStatus
                WHERE DeveloperName = 'OnBreak'
                   OR MasterLabel = 'OnBreak'
                LIMIT 1
            ];

            if (!onBreakStatuses.isEmpty()) {
                result.onBreakId = onBreakStatuses[0].Id;
            } else {
                System.debug('OmniPresenceHelper: OnBreak status not found - Check Setup > Omnichannel > Presence');
            }
        } catch (Exception e) {
            System.debug('OmniPresenceHelper: Error querying OnBreak status - ' + e.getMessage());
            // Continue to query Available status even if OnBreak fails
        }

        try {
            /**
             * Query 2: Available/Online Status (Priority: OK > Available)
             * 
             * CUSTOMIZABLE: Update DeveloperName/MasterLabel if your Org uses different names
             * Examples:
             *   Org with "Online" instead of "OK":
             *     WHERE DeveloperName = 'Online' OR MasterLabel = 'Online'
             *   Org with custom status "Ready":
             *     WHERE DeveloperName = 'Ready' OR MasterLabel = 'Ready'
             */
            List<ServicePresenceStatus> okStatuses = [
                SELECT Id, DeveloperName, MasterLabel
                FROM ServicePresenceStatus
                WHERE DeveloperName = 'OK'
                   OR MasterLabel = 'OK'
                LIMIT 1
            ];

            if (!okStatuses.isEmpty()) {
                result.availableChatId = okStatuses[0].Id;
                System.debug('OmniPresenceHelper: OK status found with ID: ' + okStatuses[0].Id);
            } else {
                /**
                 * Fallback: Search for "Available" status if "OK" not found
                 * This handles different Org configurations
                 */
                List<ServicePresenceStatus> availableStatuses = [
                    SELECT Id, DeveloperName, MasterLabel
                    FROM ServicePresenceStatus
                    WHERE DeveloperName = 'Available'
                       OR MasterLabel = 'Available'
                    LIMIT 1
                ];

                if (!availableStatuses.isEmpty()) {
                    result.availableChatId = availableStatuses[0].Id;
                    System.debug('OmniPresenceHelper: Available status found with ID: ' + availableStatuses[0].Id);
                } else {
                    System.debug('OmniPresenceHelper: OK/Available status not found - Check Setup > Omnichannel > Presence');
                }
            }
        } catch (Exception e) {
            System.debug('OmniPresenceHelper: Error querying OK/Available status - ' + e.getMessage());
            // Return partial result if available
        }

        return result;
    }
}

