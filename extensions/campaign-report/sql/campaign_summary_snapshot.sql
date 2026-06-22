/*
  File: campaign_summary_snapshot.sql
  Purpose:
    Build a single JSON snapshot with the most important campaign facts:
    lifecycle/history, flights, pricing, assets, assessments, booked players,
    delivery/reporting health, playout-order execution, and noteworthy patterns.

  Usage on a local/non-prod database:
    psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -v campaign_id=<campaign-uuid> \
      -f campaign_summary_snapshot.sql -tA > campaign-snapshot.json

  Important:
    In pi, production database access for this report must go through the configured
    `postgres_prod` MCP server. Do not use psql directly against production.
*/

WITH campaign AS (
    SELECT
        c.id,
        c.name,
        c.status,
        c.asset_status,
        c.start_date,
        c.end_date,
        c.fulfillment,
        c.performance_index,
        c.created_on,
        c.modified_on,
        c.reservation_date,
        c.reservation_expiration_date,
        c.booking_date,
        c.archived,
        c.reserve_only,
        c.confirmed,
        c.standalone,
        c.notes,
        c.price_level_report_status,
        cf.is_feasible AS campaign_is_feasible,
        cf.contacts AS feasible_contacts,
        cf.playouts AS feasible_playouts,
        cf.average_cpm AS feasible_average_cpm,
        cf.price AS feasible_price,
        cps.estimated_contacts,
        cps.estimated_playouts,
        cps.ratecard_price,
        cps.gross_price,
        cps.net_price,
        cps.netnet_price,
        cps.netnet_final_price,
        cps.netnetnet_price,
        cps.value_added_services_total,
        cps.agency_commission,
        cps.fix_price_correction_factor
    FROM dsp_campaign c
    LEFT JOIN dsp_feasibility cf ON cf.id = c.feasibility_id
    LEFT JOIN dsp_campaignpricestatistic cps ON cps.campaign_id = c.id
    WHERE c.id = :'campaign_id'::uuid
      AND c.deleted = FALSE
),
flights AS (
    SELECT
        f.id,
        f.campaign_id,
        f.name,
        f.start_date,
        f.end_date,
        f.fulfilled_date,
        f.fulfillment,
        f.performance_index,
        f.weekday_choice,
        f.asset_length,
        f.playout_frequency_density,
        f.auto_player_assignment,
        f.terminate_on_success,
        f.last_two_weeks_allocations_check,
        fg.goal AS goal_type,
        fg.amount AS goal_amount,
        fg.explicit_amount AS goal_is_explicit,
        ff.is_feasible,
        ff.contacts AS feasible_contacts,
        ff.playouts AS feasible_playouts,
        ff.average_cpm AS feasible_average_cpm,
        ff.price AS feasible_price,
        fps.estimated_contacts,
        fps.estimated_playouts,
        fps.ratecard_price,
        fps.gross_price,
        fps.net_price,
        fps.netnet_price,
        (
            SELECT COUNT(*)
            FROM application_booking b
            WHERE b.flight_id = f.id
              AND b.deleted = FALSE
        ) AS booking_count,
        (
            SELECT COUNT(DISTINCT pi.player_id)
            FROM application_booking b
            JOIN application_booking_player_inventories bpi ON bpi.booking_id = b.id
            JOIN application_playerinventory pi ON pi.id = bpi.playerinventory_id
            WHERE b.flight_id = f.id
              AND b.deleted = FALSE
              AND pi.deleted = FALSE
        ) AS booked_player_count,
        (
            SELECT COUNT(DISTINCT si.site_id)
            FROM application_booking b
            JOIN application_siteinventory si ON si.id = b.inventory_id
            WHERE b.flight_id = f.id
              AND b.deleted = FALSE
              AND si.deleted = FALSE
        ) AS booked_site_count,
        (
            SELECT COUNT(DISTINCT sga.asset_id)
            FROM dsp_spotgroup sg
            JOIN dsp_spotgroupassets sga ON sga.spot_group_id = sg.id
            WHERE sg.flight_id = f.id
              AND sg.deleted = FALSE
              AND sga.deleted = FALSE
        ) AS attached_asset_count
    FROM dsp_flight f
    LEFT JOIN dsp_flightgoal fg ON fg.flight_id = f.id
    LEFT JOIN dsp_feasibility ff ON ff.id = f.feasibility_id
    LEFT JOIN dsp_flightpricestatistic fps ON fps.flight_id = f.id
    WHERE f.campaign_id = (SELECT id FROM campaign)
      AND f.deleted = FALSE
),
booked_players AS (
    SELECT DISTINCT
        b.flight_id,
        b.id AS booking_id,
        si.id AS site_inventory_id,
        si.name AS inventory_name,
        si.site_id,
        si.network_name,
        s.name AS site_name,
        pi.id AS player_inventory_id,
        pi.player_id,
        pi.data_collection_type,
        p.name AS player_name,
        p.external_id,
        p.status AS player_status,
        p.orientation AS player_orientation,
        p.cms_connection_info_id,
        cms.name AS cms_name,
        cms.reliability_factor,
        cms.smart_performance_factor
    FROM application_booking b
    JOIN application_booking_player_inventories bpi ON bpi.booking_id = b.id
    JOIN application_playerinventory pi ON pi.id = bpi.playerinventory_id AND pi.deleted = FALSE
    JOIN application_siteinventory si ON si.id = b.inventory_id AND si.deleted = FALSE
    JOIN ssp_player p ON p.id = pi.player_id AND p.deleted = FALSE
    LEFT JOIN ssp_site s ON s.id = si.site_id AND s.deleted = FALSE
    LEFT JOIN ssp_cmsconnectioninfo cms ON cms.id = p.cms_connection_info_id AND cms.deleted = FALSE
    WHERE b.flight_id IN (SELECT id FROM flights)
      AND b.deleted = FALSE
),
assets AS (
    SELECT DISTINCT
        f.id AS flight_id,
        f.name AS flight_name,
        sg.id AS spot_group_id,
        sg.name AS spot_group_name,
        sg.percentage_share,
        a.id AS asset_id,
        a.name AS asset_name,
        a.file_name,
        a.media_type,
        a.orientation,
        a.video_duration,
        a.valid_until_date,
        a.archived,
        a.created_on AS asset_created_on,
        a.modified_on AS asset_modified_on
    FROM flights f
    JOIN dsp_spotgroup sg ON sg.flight_id = f.id AND sg.deleted = FALSE
    JOIN dsp_spotgroupassets sga ON sga.spot_group_id = sg.id AND sga.deleted = FALSE
    JOIN adserver_asset a ON a.id = sga.asset_id AND a.deleted = FALSE
),
asset_cms_links AS (
    SELECT
        acl.flight_id,
        acl.asset_id,
        acl.cms_asset_id,
        acl.feedback_service_id,
        acl.orientation,
        acl.cms_connection_id,
        acl.created_on,
        cms.name AS cms_name
    FROM application_assetcmslink acl
    LEFT JOIN ssp_cmsconnectioninfo cms ON cms.id = acl.cms_connection_id AND cms.deleted = FALSE
    WHERE acl.flight_id IN (SELECT id FROM flights)
      AND acl.deleted = FALSE
),
assessment_rows AS (
    SELECT
        a.id,
        a.campaign_id,
        a.flight_id,
        a.asset_id,
        a.asset_name,
        a.state,
        a.message,
        a.site_id,
        a.player_id,
        a.created_on,
        a.modified_on,
        p.name AS player_name,
        p.external_id,
        p.status AS player_status,
        s.name AS site_name
    FROM application_assessment a
    LEFT JOIN ssp_player p ON p.id = a.player_id AND p.deleted = FALSE
    LEFT JOIN ssp_site s ON s.id = a.site_id AND s.deleted = FALSE
    WHERE a.campaign_id = (SELECT id FROM campaign)
      AND a.deleted = FALSE
),
history_rows AS (
    SELECT
        h.id,
        h.created_on,
        h.item_type,
        h.importance,
        h.change_summary,
        h.change_details,
        h.flight_id,
        f.name AS flight_name,
        COALESCE(u.email, 'system') AS actor_email
    FROM dsp_historyitem h
    LEFT JOIN dsp_flight f ON f.id = h.flight_id
    LEFT JOIN usermgmt_user u ON u.id = h.user_id
    WHERE h.campaign_id = (SELECT id FROM campaign)
      AND h.deleted = FALSE
),
report_rows AS (
    SELECT r.*
    FROM analytics_report r
    WHERE r.flight_id IN (SELECT id FROM flights)
),
report_agg AS (
    SELECT
        COUNT(*) AS total_rows,
        COUNT(*) FILTER (
            WHERE COALESCE(actual_playouts, 0) > 0
               OR COALESCE(actual_target_contacts, 0) > 0
               OR COALESCE(actual_other_contacts, 0) > 0
               OR COALESCE(actual_price, 0) > 0
        ) AS rows_with_actuals,
        COUNT(DISTINCT day::date) FILTER (
            WHERE COALESCE(actual_playouts, 0) > 0
               OR COALESCE(actual_target_contacts, 0) > 0
               OR COALESCE(actual_other_contacts, 0) > 0
               OR COALESCE(actual_price, 0) > 0
        ) AS days_with_actuals,
        MIN(day::date) AS first_report_day,
        MAX(day::date) AS last_report_day,
        MAX(import_datetime) AS last_import_datetime,
        SUM(plan_playouts) AS total_plan_playouts,
        SUM(actual_playouts) AS total_actual_playouts,
        SUM(plan_target_contacts) AS total_plan_target_contacts,
        SUM(actual_target_contacts) AS total_actual_target_contacts,
        SUM(plan_other_contacts) AS total_plan_other_contacts,
        SUM(actual_other_contacts) AS total_actual_other_contacts,
        SUM(plan_price) AS total_plan_price,
        SUM(actual_price) AS total_actual_price,
        SUM(plan_playouts) FILTER (WHERE day::date < CURRENT_DATE) AS plan_playouts_to_date,
        SUM(actual_playouts) FILTER (WHERE day::date < CURRENT_DATE) AS actual_playouts_to_date,
        SUM(plan_target_contacts) FILTER (WHERE day::date < CURRENT_DATE) AS plan_target_contacts_to_date,
        SUM(actual_target_contacts) FILTER (WHERE day::date < CURRENT_DATE) AS actual_target_contacts_to_date,
        SUM(plan_price) FILTER (WHERE day::date < CURRENT_DATE) AS plan_price_to_date,
        SUM(actual_price) FILTER (WHERE day::date < CURRENT_DATE) AS actual_price_to_date,
        SUM(plan_playouts) FILTER (WHERE day::date >= CURRENT_DATE) AS future_plan_playouts,
        COUNT(DISTINCT day::date) FILTER (WHERE day::date >= CURRENT_DATE) AS future_planned_days,
        MAX(day::date) FILTER (
            WHERE COALESCE(actual_playouts, 0) > 0
               OR COALESCE(actual_target_contacts, 0) > 0
               OR COALESCE(actual_other_contacts, 0) > 0
               OR COALESCE(actual_price, 0) > 0
        ) AS latest_day_with_actuals
    FROM report_rows
),
per_flight_report AS (
    SELECT
        f.id AS flight_id,
        COUNT(r.id) AS report_rows,
        COUNT(r.id) FILTER (
            WHERE COALESCE(r.actual_playouts, 0) > 0
               OR COALESCE(r.actual_target_contacts, 0) > 0
               OR COALESCE(r.actual_other_contacts, 0) > 0
               OR COALESCE(r.actual_price, 0) > 0
        ) AS rows_with_actuals,
        SUM(r.plan_playouts) FILTER (WHERE r.day::date < CURRENT_DATE) AS plan_playouts_to_date,
        SUM(r.actual_playouts) FILTER (WHERE r.day::date < CURRENT_DATE) AS actual_playouts_to_date,
        SUM(r.plan_target_contacts) FILTER (WHERE r.day::date < CURRENT_DATE) AS plan_target_contacts_to_date,
        SUM(r.actual_target_contacts) FILTER (WHERE r.day::date < CURRENT_DATE) AS actual_target_contacts_to_date,
        MIN(r.day::date) AS first_report_day,
        MAX(r.day::date) AS last_report_day,
        MAX(r.import_datetime) AS last_import_datetime,
        MAX(r.day::date) FILTER (
            WHERE COALESCE(r.actual_playouts, 0) > 0
               OR COALESCE(r.actual_target_contacts, 0) > 0
               OR COALESCE(r.actual_other_contacts, 0) > 0
               OR COALESCE(r.actual_price, 0) > 0
        ) AS latest_day_with_actuals
    FROM flights f
    LEFT JOIN report_rows r ON r.flight_id = f.id
    GROUP BY f.id
),
per_player_report AS (
    SELECT
        bp.flight_id,
        bp.booking_id,
        bp.site_inventory_id,
        bp.inventory_name,
        bp.site_id,
        bp.site_name,
        bp.network_name,
        bp.player_inventory_id,
        bp.player_id,
        bp.player_name,
        bp.external_id,
        bp.player_status,
        bp.player_orientation,
        bp.data_collection_type,
        bp.cms_connection_info_id,
        bp.cms_name,
        bp.reliability_factor,
        bp.smart_performance_factor,
        COUNT(r.id) AS report_rows,
        COUNT(r.id) FILTER (
            WHERE COALESCE(r.actual_playouts, 0) > 0
               OR COALESCE(r.actual_target_contacts, 0) > 0
               OR COALESCE(r.actual_other_contacts, 0) > 0
               OR COALESCE(r.actual_price, 0) > 0
        ) AS rows_with_actuals,
        SUM(r.plan_playouts) FILTER (WHERE r.day::date < CURRENT_DATE) AS plan_playouts_to_date,
        SUM(r.actual_playouts) FILTER (WHERE r.day::date < CURRENT_DATE) AS actual_playouts_to_date,
        SUM(r.plan_target_contacts) FILTER (WHERE r.day::date < CURRENT_DATE) AS plan_target_contacts_to_date,
        SUM(r.actual_target_contacts) FILTER (WHERE r.day::date < CURRENT_DATE) AS actual_target_contacts_to_date,
        SUM(r.plan_price) FILTER (WHERE r.day::date < CURRENT_DATE) AS plan_price_to_date,
        SUM(r.actual_price) FILTER (WHERE r.day::date < CURRENT_DATE) AS actual_price_to_date,
        SUM(r.plan_playouts) FILTER (WHERE r.day::date >= CURRENT_DATE - INTERVAL '7 day' AND r.day::date < CURRENT_DATE) AS plan_playouts_last_7d,
        SUM(r.actual_playouts) FILTER (WHERE r.day::date >= CURRENT_DATE - INTERVAL '7 day' AND r.day::date < CURRENT_DATE) AS actual_playouts_last_7d,
        MAX(r.day::date) AS last_report_day,
        MAX(r.import_datetime) AS last_import_datetime,
        MAX(r.day::date) FILTER (
            WHERE COALESCE(r.actual_playouts, 0) > 0
               OR COALESCE(r.actual_target_contacts, 0) > 0
               OR COALESCE(r.actual_other_contacts, 0) > 0
               OR COALESCE(r.actual_price, 0) > 0
        ) AS latest_day_with_actuals
    FROM booked_players bp
    LEFT JOIN report_rows r
      ON r.flight_id = bp.flight_id
     AND r.player_id = bp.player_id
    GROUP BY
        bp.flight_id,
        bp.booking_id,
        bp.site_inventory_id,
        bp.inventory_name,
        bp.site_id,
        bp.site_name,
        bp.network_name,
        bp.player_inventory_id,
        bp.player_id,
        bp.player_name,
        bp.external_id,
        bp.player_status,
        bp.player_orientation,
        bp.data_collection_type,
        bp.cms_connection_info_id,
        bp.cms_name,
        bp.reliability_factor,
        bp.smart_performance_factor
),
recent_daily_report AS (
    SELECT
        r.day::date AS day,
        SUM(r.plan_playouts) AS plan_playouts,
        SUM(r.actual_playouts) AS actual_playouts,
        SUM(r.plan_target_contacts) AS plan_target_contacts,
        SUM(r.actual_target_contacts) AS actual_target_contacts,
        SUM(r.plan_price) AS plan_price,
        SUM(r.actual_price) AS actual_price
    FROM report_rows r
    WHERE r.day::date >= CURRENT_DATE - INTERVAL '14 day'
      AND r.day::date < CURRENT_DATE
    GROUP BY r.day::date
    ORDER BY r.day::date DESC
),
playout_orders AS (
    SELECT
        poh.id,
        poh.playout_time,
        poh.execution_day::date AS execution_day,
        poh.status,
        poh.cms_asset_id,
        poh.cms_connection_id,
        poh.playout_body,
        poh.playout_start,
        poh.playout_end,
        poh.flight_id
    FROM application_playoutorderhistory poh
    WHERE poh.flight_id IN (SELECT id FROM flights)
),
playout_order_agg AS (
    SELECT
        COUNT(*) AS total_rows,
        COUNT(*) FILTER (WHERE status = 'success') AS success_count,
        COUNT(*) FILTER (WHERE status = 'failure') AS failure_count,
        COUNT(*) FILTER (WHERE status = 'not_executed') AS not_executed_count,
        COUNT(DISTINCT execution_day) AS distinct_execution_days,
        MIN(execution_day) AS first_execution_day,
        MAX(execution_day) AS last_execution_day,
        MAX(playout_time) AS last_playout_time
    FROM playout_orders
),
recent_playout_orders AS (
    SELECT
        execution_day,
        COUNT(*) AS total_rows,
        COUNT(*) FILTER (WHERE status = 'success') AS success_count,
        COUNT(*) FILTER (WHERE status = 'failure') AS failure_count,
        COUNT(*) FILTER (WHERE status = 'not_executed') AS not_executed_count,
        MAX(playout_time) AS last_playout_time
    FROM playout_orders
    WHERE execution_day >= CURRENT_DATE - INTERVAL '14 day'
    GROUP BY execution_day
    ORDER BY execution_day DESC
),
history_event_counts AS (
    SELECT
        item_type,
        COUNT(*) AS item_count
    FROM history_rows
    GROUP BY item_type
),
asset_state_summary AS (
    SELECT
        asset_id,
        COUNT(*) AS assessment_count,
        COUNT(*) FILTER (WHERE state = 'pending') AS pending_count,
        COUNT(*) FILTER (WHERE state = 'accepted') AS accepted_count,
        COUNT(*) FILTER (WHERE state = 'rejected') AS rejected_count,
        JSONB_AGG(
            JSONB_BUILD_OBJECT(
                'assessment_id', id,
                'flight_id', flight_id,
                'site_id', site_id,
                'site_name', site_name,
                'player_id', player_id,
                'player_name', player_name,
                'player_status', player_status,
                'state', state,
                'message', NULLIF(message, ''),
                'created_on', created_on,
                'modified_on', modified_on
            )
            ORDER BY site_name, player_name
        ) AS assessment_rows
    FROM assessment_rows
    GROUP BY asset_id
),
anomaly_rows AS (
    SELECT 10 AS sort_order, 'high' AS severity, 'no_actual_delivery_to_date' AS code,
           FORMAT(
               'Campaign has planned delivery to date (playouts=%s, contacts=%s) but zero actual delivery to date.',
               COALESCE((SELECT plan_playouts_to_date::bigint FROM report_agg), 0),
               COALESCE((SELECT plan_target_contacts_to_date::bigint FROM report_agg), 0)
           ) AS message
    WHERE COALESCE((SELECT plan_playouts_to_date FROM report_agg), 0) > 0
      AND COALESCE((SELECT actual_playouts_to_date FROM report_agg), 0) = 0
      AND COALESCE((SELECT actual_target_contacts_to_date FROM report_agg), 0) = 0

    UNION ALL

    SELECT 20, 'high', 'all_booked_players_inactive',
           FORMAT('All %s booked players are inactive.', COALESCE((SELECT COUNT(*) FROM booked_players), 0))
    WHERE EXISTS (SELECT 1 FROM booked_players)
      AND NOT EXISTS (SELECT 1 FROM booked_players WHERE player_status IS DISTINCT FROM 'inactive')

    UNION ALL

    SELECT 30, 'medium', 'reports_have_only_plans',
           FORMAT(
               'Analytics report has %s rows, but none contain actual playout/contact/price data.',
               COALESCE((SELECT total_rows FROM report_agg), 0)
           )
    WHERE COALESCE((SELECT total_rows FROM report_agg), 0) > 0
      AND COALESCE((SELECT rows_with_actuals FROM report_agg), 0) = 0

    UNION ALL

    SELECT 40, 'medium', 'playout_orders_but_no_history_event',
           'Playout order history exists, but campaign history has no PLAYOUT_PLANS_SENT event.'
    WHERE EXISTS (SELECT 1 FROM playout_orders)
      AND NOT EXISTS (SELECT 1 FROM history_rows WHERE item_type = 'playout_plans_sent')

    UNION ALL

    SELECT 50, 'medium', 'accepted_assessments_without_history_event',
           'All current assessments are accepted, but campaign history has no ASSET_APPROVED event.'
    WHERE EXISTS (SELECT 1 FROM assessment_rows)
      AND NOT EXISTS (SELECT 1 FROM assessment_rows WHERE state <> 'accepted')
      AND NOT EXISTS (SELECT 1 FROM history_rows WHERE item_type = 'asset_approved')

    UNION ALL

    SELECT 60, 'medium', 'running_with_zero_performance_fields',
           FORMAT(
               'Campaign status is %s, but campaign performance_index=%s and fulfillment=%s.',
               (SELECT status FROM campaign),
               COALESCE((SELECT performance_index FROM campaign), 0),
               COALESCE((SELECT fulfillment FROM campaign), 0)
           )
    WHERE (SELECT status FROM campaign) IN ('running', 'finished')
      AND COALESCE((SELECT performance_index FROM campaign), 0) = 0
      AND COALESCE((SELECT fulfillment FROM campaign), 0) = 0

    UNION ALL

    SELECT 70, 'medium', 'player_missing_actuals',
           FORMAT(
               'Player %s has planned playouts to date (%s) but zero actual playouts to date.',
               ppr.player_name,
               COALESCE(ppr.plan_playouts_to_date::bigint, 0)
           )
    FROM per_player_report ppr
    WHERE COALESCE(ppr.plan_playouts_to_date, 0) > 0
      AND COALESCE(ppr.actual_playouts_to_date, 0) = 0
),
summary AS (
    SELECT JSONB_BUILD_OBJECT(
        'generated_at', NOW(),
        'campaign', (SELECT TO_JSONB(campaign) FROM campaign),
        'counts', JSONB_BUILD_OBJECT(
            'flight_count', (SELECT COUNT(*) FROM flights),
            'history_item_count', (SELECT COUNT(*) FROM history_rows),
            'asset_count', (SELECT COUNT(DISTINCT asset_id) FROM assets),
            'assessment_count', (SELECT COUNT(*) FROM assessment_rows),
            'booked_player_count', (SELECT COUNT(DISTINCT player_id) FROM booked_players),
            'booked_site_count', (SELECT COUNT(DISTINCT site_id) FROM booked_players),
            'cms_link_count', (SELECT COUNT(*) FROM asset_cms_links),
            'playout_order_count', (SELECT COUNT(*) FROM playout_orders),
            'report_row_count', (SELECT COALESCE(total_rows, 0) FROM report_agg)
        ),
        'flights', COALESCE((
            SELECT JSONB_AGG(
                TO_JSONB(f) || JSONB_BUILD_OBJECT(
                    'reporting', (
                        SELECT TO_JSONB(pfr) - 'flight_id'
                        FROM per_flight_report pfr
                        WHERE pfr.flight_id = f.id
                    )
                )
                ORDER BY f.start_date, f.name
            )
            FROM flights f
        ), '[]'::jsonb),
        'history', JSONB_BUILD_OBJECT(
            'event_counts', COALESCE((
                SELECT JSONB_OBJECT_AGG(item_type, item_count)
                FROM history_event_counts
            ), '{}'::jsonb),
            'items', COALESCE((
                SELECT JSONB_AGG(TO_JSONB(hr) ORDER BY hr.created_on)
                FROM history_rows hr
            ), '[]'::jsonb)
        ),
        'assets', COALESCE((
            SELECT JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'asset_id', a.asset_id,
                    'asset_name', a.asset_name,
                    'file_name', a.file_name,
                    'media_type', a.media_type,
                    'orientation', a.orientation,
                    'video_duration', a.video_duration,
                    'valid_until_date', a.valid_until_date,
                    'archived', a.archived,
                    'asset_created_on', a.asset_created_on,
                    'asset_modified_on', a.asset_modified_on,
                    'attached_to', (
                        SELECT COALESCE(JSONB_AGG(JSONB_BUILD_OBJECT(
                            'flight_id', a2.flight_id,
                            'flight_name', a2.flight_name,
                            'spot_group_id', a2.spot_group_id,
                            'spot_group_name', a2.spot_group_name,
                            'percentage_share', a2.percentage_share
                        ) ORDER BY a2.flight_name, a2.spot_group_name), '[]'::jsonb)
                        FROM assets a2
                        WHERE a2.asset_id = a.asset_id
                    ),
                    'cms_links', (
                        SELECT COALESCE(JSONB_AGG(TO_JSONB(acl) - 'asset_id' ORDER BY acl.created_on), '[]'::jsonb)
                        FROM asset_cms_links acl
                        WHERE acl.asset_id = a.asset_id
                    ),
                    'assessment_summary', (
                        SELECT TO_JSONB(ass) - 'asset_id'
                        FROM asset_state_summary ass
                        WHERE ass.asset_id = a.asset_id
                    )
                )
                ORDER BY a.asset_name, a.asset_id
            )
            FROM (
                SELECT DISTINCT ON (asset_id)
                    asset_id,
                    asset_name,
                    file_name,
                    media_type,
                    orientation,
                    video_duration,
                    valid_until_date,
                    archived,
                    asset_created_on,
                    asset_modified_on
                FROM assets
                ORDER BY asset_id, asset_name
            ) a
        ), '[]'::jsonb),
        'assessments', JSONB_BUILD_object(
            'by_state', JSONB_BUILD_OBJECT(
                'pending', (SELECT COUNT(*) FROM assessment_rows WHERE state = 'pending'),
                'accepted', (SELECT COUNT(*) FROM assessment_rows WHERE state = 'accepted'),
                'rejected', (SELECT COUNT(*) FROM assessment_rows WHERE state = 'rejected')
            ),
            'rows', COALESCE((
                SELECT JSONB_AGG(TO_JSONB(ar) ORDER BY ar.asset_name, ar.site_name, ar.player_name)
                FROM assessment_rows ar
            ), '[]'::jsonb)
        ),
        'booked_players', COALESCE((
            SELECT JSONB_AGG(
                TO_JSONB(ppr) || JSONB_BUILD_OBJECT(
                    'delivery_pct_to_date', CASE
                        WHEN COALESCE(ppr.plan_playouts_to_date, 0) > 0
                        THEN ROUND((100.0 * COALESCE(ppr.actual_playouts_to_date, 0) / ppr.plan_playouts_to_date)::numeric, 2)
                        ELSE NULL
                    END,
                    'delivery_pct_last_7d', CASE
                        WHEN COALESCE(ppr.plan_playouts_last_7d, 0) > 0
                        THEN ROUND((100.0 * COALESCE(ppr.actual_playouts_last_7d, 0) / ppr.plan_playouts_last_7d)::numeric, 2)
                        ELSE NULL
                    END
                )
                ORDER BY ppr.site_name, ppr.player_name
            )
            FROM per_player_report ppr
        ), '[]'::jsonb),
        'reporting', JSONB_BUILD_OBJECT(
            'overall', (SELECT TO_JSONB(report_agg) FROM report_agg),
            'delivery_to_date_pct', JSONB_BUILD_OBJECT(
                'playouts', CASE
                    WHEN COALESCE((SELECT plan_playouts_to_date FROM report_agg), 0) > 0
                    THEN ROUND((100.0 * COALESCE((SELECT actual_playouts_to_date FROM report_agg), 0) / (SELECT plan_playouts_to_date FROM report_agg))::numeric, 2)
                    ELSE NULL
                END,
                'target_contacts', CASE
                    WHEN COALESCE((SELECT plan_target_contacts_to_date FROM report_agg), 0) > 0
                    THEN ROUND((100.0 * COALESCE((SELECT actual_target_contacts_to_date FROM report_agg), 0) / (SELECT plan_target_contacts_to_date FROM report_agg))::numeric, 2)
                    ELSE NULL
                END,
                'price', CASE
                    WHEN COALESCE((SELECT plan_price_to_date FROM report_agg), 0) > 0
                    THEN ROUND((100.0 * COALESCE((SELECT actual_price_to_date FROM report_agg), 0) / (SELECT plan_price_to_date FROM report_agg))::numeric, 2)
                    ELSE NULL
                END
            ),
            'recent_daily', COALESCE((
                SELECT JSONB_AGG(
                    TO_JSONB(rdr) || JSONB_BUILD_OBJECT(
                        'playout_delivery_pct', CASE
                            WHEN COALESCE(rdr.plan_playouts, 0) > 0
                            THEN ROUND((100.0 * COALESCE(rdr.actual_playouts, 0) / rdr.plan_playouts)::numeric, 2)
                            ELSE NULL
                        END,
                        'target_contact_delivery_pct', CASE
                            WHEN COALESCE(rdr.plan_target_contacts, 0) > 0
                            THEN ROUND((100.0 * COALESCE(rdr.actual_target_contacts, 0) / rdr.plan_target_contacts)::numeric, 2)
                            ELSE NULL
                        END,
                        'price_delivery_pct', CASE
                            WHEN COALESCE(rdr.plan_price, 0) > 0
                            THEN ROUND((100.0 * COALESCE(rdr.actual_price, 0) / rdr.plan_price)::numeric, 2)
                            ELSE NULL
                        END
                    )
                    ORDER BY rdr.day DESC
                )
                FROM recent_daily_report rdr
            ), '[]'::jsonb)
        ),
        'playout_orders', JSONB_BUILD_OBJECT(
            'overall', (SELECT TO_JSONB(playout_order_agg) FROM playout_order_agg),
            'recent_daily', COALESCE((
                SELECT JSONB_AGG(TO_JSONB(rpo) ORDER BY rpo.execution_day DESC)
                FROM recent_playout_orders rpo
            ), '[]'::jsonb)
        ),
        'noteworthy_patterns', COALESCE((
            SELECT JSONB_AGG(
                JSONB_BUILD_OBJECT(
                    'severity', severity,
                    'code', code,
                    'message', message
                )
                ORDER BY sort_order, code
            )
            FROM anomaly_rows
        ), '[]'::jsonb)
    ) AS payload
)
SELECT payload AS summary
FROM summary;
