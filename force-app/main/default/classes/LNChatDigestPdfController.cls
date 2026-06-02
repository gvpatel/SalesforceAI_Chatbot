/**
 * Controller for the LNChatDigestPdf Visualforce page (rendered as PDF and
 * attached to the weekly digest email by LNChatDigestBatch).
 *
 * Data is passed via static fields set in the SAME transaction immediately
 * before Page.LNChatDigestPdf.getContentAsPDF() — statics persist across the
 * synchronous getContentAsPDF render, so the page can read them.
 */
public with sharing class LNChatDigestPdfController {
  public static String repNameVal;
  public static String digestDateVal;
  public static String insightsVal;
  public static List<Map<String, Object>> rowsVal;

  public String getRepName() {
    return repNameVal;
  }

  public String getDigestDate() {
    return digestDateVal;
  }

  public String getInsights() {
    return insightsVal;
  }

  public Boolean getHasInsights() {
    return String.isNotBlank(insightsVal);
  }

  public List<Map<String, Object>> getRows() {
    return rowsVal != null ? rowsVal : new List<Map<String, Object>>();
  }
}
