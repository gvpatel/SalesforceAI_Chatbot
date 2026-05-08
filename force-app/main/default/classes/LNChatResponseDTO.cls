public with sharing class LNChatResponseDTO {
    public String responseType { get; set; }
    public String title { get; set; }
    public String summary { get; set; }
    public Map<String, Object> data { get; set; }
    public List<ActionDTO> actions { get; set; }
    public String rawJson { get; set; }

    public class ActionDTO {
        public String label { get; set; }
        public String flowApiName { get; set; }
        public Map<String, Object> inputVariables { get; set; }

        public ActionDTO() {
            this.inputVariables = new Map<String, Object>();
        }
    }

    public LNChatResponseDTO() {
        this.actions = new List<ActionDTO>();
        this.data = new Map<String, Object>();
    }

    public static LNChatResponseDTO fromJson(String jsonString) {
        if (String.isBlank(jsonString)) {
            return buildErrorDTO('Empty response from AI service');
        }

        LNChatResponseDTO dto = new LNChatResponseDTO();
        dto.rawJson = jsonString;

        try {
            Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonString);

            dto.responseType = (String) parsed.get('responseType');
            dto.title = (String) parsed.get('title');
            dto.summary = (String) parsed.get('summary');

            Object dataObj = parsed.get('data');
            if (dataObj instanceof Map<String, Object>) {
                dto.data = (Map<String, Object>) dataObj;
            } else {
                dto.data = new Map<String, Object>();
            }

            Object actionsObj = parsed.get('actions');
            dto.actions = new List<ActionDTO>();
            if (actionsObj instanceof List<Object>) {
                for (Object actionItem : (List<Object>) actionsObj) {
                    if (actionItem instanceof Map<String, Object>) {
                        Map<String, Object> actionMap = (Map<String, Object>) actionItem;
                        ActionDTO action = new ActionDTO();
                        action.label = (String) actionMap.get('label');
                        action.flowApiName = (String) actionMap.get('flowApiName');
                        Object inputVarsObj = actionMap.get('inputVariables');
                        if (inputVarsObj instanceof Map<String, Object>) {
                            action.inputVariables = (Map<String, Object>) inputVarsObj;
                        }
                        dto.actions.add(action);
                    }
                }
            }

            if (String.isBlank(dto.responseType)) {
                dto.responseType = 'summary';
            }

        } catch (Exception e) {
            return buildErrorDTO('Failed to parse AI response: ' + e.getMessage());
        }

        return dto;
    }

    private static LNChatResponseDTO buildErrorDTO(String errorMessage) {
        LNChatResponseDTO dto = new LNChatResponseDTO();
        dto.responseType = 'alert';
        dto.title = 'Error';
        dto.summary = errorMessage;
        dto.data = new Map<String, Object>{
            'severity' => 'critical',
            'alertTitle' => 'AI Response Error',
            'message' => errorMessage,
            'details' => new List<String>{ errorMessage }
        };
        dto.actions = new List<ActionDTO>();
        dto.rawJson = '{}';
        return dto;
    }
}
